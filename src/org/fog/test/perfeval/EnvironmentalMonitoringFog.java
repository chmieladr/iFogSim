package org.fog.test.perfeval;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;

import org.cloudbus.cloudsim.Host;
import org.cloudbus.cloudsim.Log;
import org.cloudbus.cloudsim.Pe;
import org.cloudbus.cloudsim.Storage;
import org.cloudbus.cloudsim.core.CloudSim;
import org.cloudbus.cloudsim.power.PowerHost;
import org.cloudbus.cloudsim.provisioners.RamProvisionerSimple;
import org.cloudbus.cloudsim.sdn.overbooking.BwProvisionerOverbooking;
import org.cloudbus.cloudsim.sdn.overbooking.PeProvisionerOverbooking;
import org.fog.application.AppEdge;
import org.fog.application.AppLoop;
import org.fog.application.Application;
import org.fog.application.selectivity.FractionalSelectivity;
import org.fog.entities.Actuator;
import org.fog.entities.FogBroker;
import org.fog.entities.FogDevice;
import org.fog.entities.FogDeviceCharacteristics;
import org.fog.entities.Sensor;
import org.fog.entities.Tuple;
import org.fog.placement.Controller;
import org.fog.placement.ModuleMapping;
import org.fog.placement.ModulePlacementEdgewards;
import org.fog.placement.ModulePlacementMapping;
import org.fog.policy.AppModuleAllocationPolicy;
import org.fog.scheduler.StreamOperatorScheduler;
import org.fog.utils.Config;
import org.fog.utils.FogLinearPowerModel;
import org.fog.utils.FogUtils;
import org.fog.utils.NetworkUsageMonitor;
import org.fog.utils.TimeKeeper;
import org.fog.utils.distribution.DeterministicDistribution;

/**
 * Smart-building environmental monitoring: temperature/humidity sensors feed a
 * simple processing pipeline (filter → anomaly detector → alarm). Static fog
 * topology — no mobility dataset. Used to compare Cloud-only placement against
 * {@link ModulePlacementEdgewards}.
 */
public class EnvironmentalMonitoringFog {
    static List<FogDevice> fogDevices = new ArrayList<>();
    static List<Sensor> sensors = new ArrayList<>();
    static List<Actuator> actuators = new ArrayList<>();
    static int numGateways = 1;
    static int sensorsPerGateway = 1;

    /**
     * Fraction of filtered readings that trigger an alarm (anomaly_detector selectivity).
     * Default 1.0 preserves the original "every reading is an anomaly" behavior.
     * Lower values (e.g. 0.1) model sparse real-world anomalies: most tuples pass through
     * the filter but only a fraction reach the alarm actuator, reducing downstream load.
     */
    static double anomalySelectivity = 1.0;

    /** When true, all modules run in the cloud (naive baseline). */
    private static boolean CLOUD = false;

    public static void main(String[] args) {
        // CLI args let run_experiments.sh sweep configs without recompiling.
        for (String arg : args) {
            if (arg.startsWith("--cloud=")) CLOUD = Boolean.parseBoolean(arg.split("=")[1]);
            if (arg.startsWith("--gateways=")) numGateways = Integer.parseInt(arg.split("=")[1]);
            if (arg.startsWith("--sensors-per-gateway="))
                sensorsPerGateway = Integer.parseInt(arg.split("=")[1]);
            if (arg.startsWith("--anomaly-selectivity="))
                anomalySelectivity = Double.parseDouble(arg.split("=")[1]);
        }

        Log.printLine("Starting EnvironmentalMonitoringFog...");

        try {
            Log.disable();
            int num_user = 1;
            Calendar calendar = Calendar.getInstance();
            boolean trace_flag = false;

            CloudSim.init(num_user, calendar, trace_flag);

            String appId = "env-monitor";

            FogBroker broker = new FogBroker("broker");

            Application application = createApplication(appId, broker.getId(), anomalySelectivity);
            application.setUserId(broker.getId());

            createFogDevices(broker.getId(), appId);

            // Seed placement: pin data_filter to each gateway so Fog runs close to sensors.
            ModuleMapping moduleMapping = ModuleMapping.createModuleMapping();
            for (FogDevice device : fogDevices) {
                if (device.getName().startsWith("g-")) {
                    moduleMapping.addModuleToDevice("data_filter", device.getName());
                }
            }
            if (CLOUD) {
                moduleMapping.addModuleToDevice("data_filter", "cloud");
                moduleMapping.addModuleToDevice("anomaly_detector", "cloud");
            }

            Controller controller = new Controller("master-controller", fogDevices, sensors, actuators);

            controller.submitApplication(application,
                    (CLOUD) ? (new ModulePlacementMapping(fogDevices, application, moduleMapping))
                            : (new ModulePlacementEdgewards(fogDevices, sensors, actuators, application, moduleMapping)));

            TimeKeeper.getInstance().setSimulationStartTime(Calendar.getInstance().getTimeInMillis());

            // Controller ends with System.exit(0), so export runs in a shutdown hook.
            final int capturedGateways = numGateways;
            final int capturedSensors = sensorsPerGateway;
            final double capturedSelectivity = anomalySelectivity;
            Runtime.getRuntime().addShutdownHook(new Thread(
                    () -> exportResultsToCsv("EnvironmentalMonitoring",
                            CLOUD ? "Cloud" : "Fog", capturedGateways, capturedSensors,
                            capturedSelectivity)));

            CloudSim.startSimulation();

            CloudSim.stopSimulation();

            Log.printLine("EnvironmentalMonitoringFog finished!");
        } catch (Exception e) {
            e.printStackTrace();
            Log.printLine("Unwanted errors happen");
            System.exit(1);
        }
    }

    /** Appends one result row to results_EnvironmentalMonitoring.csv (used by the experiment script). */
    private static void exportResultsToCsv(String appType, String strategy,
                                           int gateways, int sensorsPerGw,
                                           double selectivity) {
        double totalLatency = 0.0;
        int loopCount = 0;
        for (Map.Entry<Integer, Double> entry :
                TimeKeeper.getInstance().getLoopIdToCurrentAverage().entrySet()) {
            if (entry.getValue() != null) {
                totalLatency += entry.getValue();
                loopCount++;
            }
        }
        // -1 means no AppLoop finished (same convention as CrowdSensing export).
        double avgLatency = (loopCount > 0) ? (totalLatency / loopCount) : -1.0;

        double networkUsage = NetworkUsageMonitor.getNetworkUsage() / Config.MAX_SIMULATION_TIME;

        double totalEnergy = 0.0;
        for (FogDevice fd : fogDevices) {
            totalEnergy += fd.getEnergyConsumption();
        }

        double cloudCost = 0.0;
        for (FogDevice fd : fogDevices) {
            if ("cloud".equals(fd.getName())) {
                cloudCost = fd.getTotalCost();
                break;
            }
        }

        File file = new File("results_EnvironmentalMonitoring.csv");
        boolean shouldWriteHeader = !file.exists();
        try (FileWriter fw = new FileWriter(file, true)) {
            if (shouldWriteHeader)
                fw.write("AppType,Strategy,NumGateways,SensorsPerGateway,AnomalySelectivity,AvgLoopLatency(ms),NetworkUsage,TotalEnergy(W),CloudExecutionCost\n");

            fw.write(String.format("%s,%s,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f%n",
                    appType, strategy, gateways, sensorsPerGw, selectivity,
                    avgLatency, networkUsage, totalEnergy, cloudCost));
            System.out.println("[CSV Exporter] Results appended to " + file.getAbsolutePath());
        } catch (IOException e) {
            System.err.println("[CSV Exporter] Failed to write results_EnvironmentalMonitoring.csv: " + e.getMessage());
        }
    }

    /** cloud → proxy → gateways; same hierarchy pattern as DCNSFog. */
    private static void createFogDevices(int userId, String appId) {
        FogDevice cloud = createFogDevice("cloud", 44800, 40000, 100, 10000, 0, 0.01, 16 * 103, 16 * 83.25);
        cloud.setParentId(-1);
        fogDevices.add(cloud);

        FogDevice proxy = createFogDevice("proxy-server", 2800, 4000, 10000, 10000, 1, 0.0, 107.339, 83.4333);
        proxy.setParentId(cloud.getId());
        proxy.setUplinkLatency(100); // ms to cloud
        fogDevices.add(proxy);

        for (int g = 0; g < numGateways; g++) {
            addGateway(String.valueOf(g), userId, appId, proxy.getId());
        }
    }

    private static void addGateway(String id, int userId, String appId, int parentId) {
        FogDevice gateway = createFogDevice("g-" + id, 2800, 4000, 10000, 10000, 1, 0.0, 107.339, 83.4333);
        gateway.setParentId(parentId);
        gateway.setUplinkLatency(2);
        fogDevices.add(gateway);

        for (int s = 0; s < sensorsPerGateway; s++) {
            String sensorId = id + "-" + s;
            // One reading every 10 ms; tuple type must match createApplication() edges.
            Sensor sensor = new Sensor("s-" + sensorId, "ENV_SENSOR", userId, appId,
                    new DeterministicDistribution(10));
            sensors.add(sensor);
            sensor.setGatewayDeviceId(gateway.getId());
            sensor.setLatency(1.0);

            Actuator alarm = new Actuator("alarm-" + sensorId, userId, appId, "ALARM_ACTUATOR");
            actuators.add(alarm);
            alarm.setGatewayDeviceId(gateway.getId());
            alarm.setLatency(1.0);
        }
    }

    private static FogDevice createFogDevice(String nodeName, long mips,
                                             int ram, long upBw, long downBw, int level,
                                             double ratePerMips, double busyPower, double idlePower) {
        List<Pe> peList = new ArrayList<>();
        peList.add(new Pe(0, new PeProvisionerOverbooking(mips)));

        int hostId = FogUtils.generateEntityId();
        long storage = 1000000;
        int bw = 10000;

        PowerHost host = new PowerHost(
                hostId,
                new RamProvisionerSimple(ram),
                new BwProvisionerOverbooking(bw),
                storage,
                peList,
                new StreamOperatorScheduler(peList),
                new FogLinearPowerModel(busyPower, idlePower)
        );

        List<Host> hostList = new ArrayList<>();
        hostList.add(host);

        String arch = "x86";
        String os = "Linux";
        String vmm = "Xen";
        double time_zone = 10.0;
        double cost = 3.0;
        double costPerMem = 0.05;
        double costPerStorage = 0.001;
        double costPerBw = 0.0;
        LinkedList<Storage> storageList = new LinkedList<>();

        FogDeviceCharacteristics characteristics = new FogDeviceCharacteristics(
                arch, os, vmm, host, time_zone, cost, costPerMem,
                costPerStorage, costPerBw);

        FogDevice fogdevice = null;
        try {
            fogdevice = new FogDevice(nodeName, characteristics,
                    new AppModuleAllocationPolicy(hostList), storageList, 10, upBw, downBw, 0, ratePerMips);
        } catch (Exception e) {
            e.printStackTrace();
        }

        fogdevice.setLevel(level);
        return fogdevice;
    }

    @SuppressWarnings({"serial"})
    private static Application createApplication(String appId, int userId, double anomalyRate) {
        Application application = Application.createApplication(appId, userId);

        // RAM (MB), MIPS, uplink bandwidth — anomaly_detector is the heavier stage.
        application.addAppModule("data_filter", 10, 500, 10000);
        application.addAppModule("anomaly_detector", 10, 1500, 10000);

        application.addAppEdge("ENV_SENSOR", "data_filter", 200, 500, "ENV_SENSOR", Tuple.UP, AppEdge.SENSOR);
        application.addAppEdge("data_filter", "anomaly_detector", 500, 500, "FILTERED_READING", Tuple.UP, AppEdge.MODULE);
        application.addAppEdge("anomaly_detector", "ALARM_ACTUATOR", 100, 50, "ALARM_SIGNAL", Tuple.DOWN, AppEdge.ACTUATOR);

        application.addTupleMapping("data_filter", "ENV_SENSOR", "FILTERED_READING", new FractionalSelectivity(1.0));
        // Sparse anomaly model: only anomalyRate fraction of filtered readings emit ALARM_SIGNAL.
        application.addTupleMapping("anomaly_detector", "FILTERED_READING", "ALARM_SIGNAL",
                new FractionalSelectivity(anomalyRate));

        // Latency metric: filter → detector → alarm (sensor ingress is outside the loop).
        final AppLoop loop = new AppLoop(new ArrayList<String>() {{
            add("data_filter");
            add("anomaly_detector");
            add("ALARM_ACTUATOR");
        }});
        application.setLoops(new ArrayList<AppLoop>() {{
            add(loop);
        }});

        return application;
    }
}
