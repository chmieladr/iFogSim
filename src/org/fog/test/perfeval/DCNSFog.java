package org.fog.test.perfeval;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.LinkedList;
import java.util.List;

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

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.Map;

/**
 * Simulation setup for case study 2 - Intelligent Surveillance
 *
 * @author Harshit Gupta
 *
 */
public class DCNSFog {
    static List<FogDevice> fogDevices = new ArrayList<FogDevice>();
    static List<Sensor> sensors = new ArrayList<Sensor>();
    static List<Actuator> actuators = new ArrayList<Actuator>();
    static int numOfAreas = 1;
    static int numOfCamerasPerArea = 4;

    private static boolean CLOUD = false;

    public static void main(String[] args) {
        // Accept args to drive experiments from a script without recompiling between runs.
        for (String arg : args) {
            if (arg.startsWith("--cloud=")) CLOUD = Boolean.parseBoolean(arg.split("=")[1]);
            if (arg.startsWith("--areas=")) numOfAreas = Integer.parseInt(arg.split("=")[1]);
            if (arg.startsWith("--cameras=")) numOfCamerasPerArea = Integer.parseInt(arg.split("=")[1]);
        }

        Log.printLine("Starting DCNS...");

        try {
            Log.disable();
            int num_user = 1; // number of cloud users
            Calendar calendar = Calendar.getInstance();
            boolean trace_flag = false; // mean trace events

            CloudSim.init(num_user, calendar, trace_flag);

            String appId = "dcns"; // identifier of the application

            FogBroker broker = new FogBroker("broker");

            Application application = createApplication(appId, broker.getId());
            application.setUserId(broker.getId());

            createFogDevices(broker.getId(), appId);

            Controller controller = null;

            ModuleMapping moduleMapping = ModuleMapping.createModuleMapping(); // initializing a module mapping
            for (FogDevice device : fogDevices) {
                if (device.getName().startsWith("m")) { // names of all Smart Cameras start with 'm'
                    moduleMapping.addModuleToDevice("motion_detector", device.getName());  // fixing 1 instance of the Motion Detector module to each Smart Camera
                }
            }
            moduleMapping.addModuleToDevice("user_interface", "cloud"); // fixing instances of User Interface module in the Cloud
            if (CLOUD) {
                // if the mode of deployment is cloud-based
                moduleMapping.addModuleToDevice("object_detector", "cloud"); // placing all instances of Object Detector module in the Cloud
                moduleMapping.addModuleToDevice("object_tracker", "cloud"); // placing all instances of Object Tracker module in the Cloud
            }

            controller = new Controller("master-controller", fogDevices, sensors,
                    actuators);

            controller.submitApplication(application,
                    (CLOUD) ? (new ModulePlacementMapping(fogDevices, application, moduleMapping))
                            : (new ModulePlacementEdgewards(fogDevices, sensors, actuators, application, moduleMapping)));

            TimeKeeper.getInstance().setSimulationStartTime(Calendar.getInstance().getTimeInMillis());

            // The controller calls System.exit(0) when the simulation ends, so
            // startSimulation() never returns. A shutdown hook is the only way to
            // run export code after the simulation without touching controller code.
            final int capturedAreas = numOfAreas;
            final int capturedCameras = numOfCamerasPerArea;
            Runtime.getRuntime().addShutdownHook(new Thread(
                    () -> exportResultsToCsv("DCNS", CLOUD ? "Cloud" : "Fog", capturedAreas, capturedCameras)));

            CloudSim.startSimulation();

            CloudSim.stopSimulation();

            Log.printLine("VRGame finished!");
        } catch (Exception e) {
            e.printStackTrace();
            Log.printLine("Unwanted errors happen");
            System.exit(1);
        }
    }

    /**
     * Appends one row of results to the unified {@code results_DCNS.csv},
     * creating the file with a header if it doesn't exist yet.
     * <p>
     * Columns: AppType, Strategy, NumAreas, NumCamerasPerArea,
     * Loop1Latency(ms), Loop2Latency(ms), CompletedLoops1, CompletedLoops2,
     * NetworkUsage, TotalEnergy(W), CloudExecutionCost.
     * <p>
     * Loop IDs are sorted ascending (registration order):
     * Loop1 is the motion_detector -> object_detector -> object_tracker path
     * Loop2 is the object_tracker -> PTZ_CONTROL path.
     * Latency of -1.0 means no tuple completed that path within the simulation window
     * (null loop — measurement artifact).
     */
    private static void exportResultsToCsv(String appType, String strategy, int numAreas, int numCameras) {
        Map<Integer, Double> loopAverages = TimeKeeper.getInstance().getLoopIdToCurrentAverage();
        List<Integer> loopIds = new ArrayList<>(loopAverages.keySet());
        Collections.sort(loopIds);

        double loop1Latency = -1.0;
        double loop2Latency = -1.0;
        int completedLoop1 = 0;
        int completedLoop2 = 0;

        if (loopIds.size() >= 1) {
            Double v1 = loopAverages.get(loopIds.get(0));
            if (v1 != null) {
                loop1Latency = v1;
                completedLoop1 = 1;
            }
        }
        if (loopIds.size() >= 2) {
            Double v2 = loopAverages.get(loopIds.get(1));
            if (v2 != null) {
                loop2Latency = v2;
                completedLoop2 = 1;
            }
        }

        int completed = completedLoop1 + completedLoop2;
        if (completed < loopIds.size())
            System.err.printf("[CSV Exporter] WARNING: only %d of %d AppLoops completed "
                            + "(null loops excluded from latency columns).%n",
                    completed, loopIds.size());

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

        File file = new File("results_DCNS.csv");
        boolean shouldWriteHeader = !file.exists();
        try (FileWriter fw = new FileWriter(file, true)) {
            if (shouldWriteHeader)
                fw.write("AppType,Strategy,NumAreas,NumCamerasPerArea,Loop1Latency(ms),Loop2Latency(ms),CompletedLoops1,CompletedLoops2,NetworkUsage,TotalEnergy(W),CloudExecutionCost\n");

            fw.write(String.format("%s,%s,%d,%d,%.4f,%.4f,%d,%d,%.4f,%.4f,%.4f%n",
                    appType, strategy, numAreas, numCameras,
                    loop1Latency, loop2Latency, completedLoop1, completedLoop2,
                    networkUsage, totalEnergy, cloudCost));
            System.out.println("[CSV Exporter] Results appended to " + file.getAbsolutePath());
        } catch (IOException e) {
            System.err.println("[CSV Exporter] Failed to write results.csv: " + e.getMessage());
        }
    }

    /**
     * Creates the fog devices in the physical topology of the simulation.
     *
     * @param userId
     * @param appId
     */
    private static void createFogDevices(int userId, String appId) {
        FogDevice cloud = createFogDevice("cloud", 44800, 40000, 100, 10000, 0, 0.01, 16 * 103, 16 * 83.25);
        cloud.setParentId(-1);
        fogDevices.add(cloud);
        FogDevice proxy = createFogDevice("proxy-server", 2800, 4000, 10000, 10000, 1, 0.0, 107.339, 83.4333);
        proxy.setParentId(cloud.getId());
        proxy.setUplinkLatency(100); // latency of connection between proxy server and cloud is 100 ms
        fogDevices.add(proxy);
        for (int i = 0; i < numOfAreas; i++) {
            addArea(i + "", userId, appId, proxy.getId());
        }
    }

    private static FogDevice addArea(String id, int userId, String appId, int parentId) {
        FogDevice router = createFogDevice("d-" + id, 2800, 4000, 10000, 10000, 1, 0.0, 107.339, 83.4333);
        fogDevices.add(router);
        router.setUplinkLatency(2); // latency of connection between router and proxy server is 2 ms
        for (int i = 0; i < numOfCamerasPerArea; i++) {
            String mobileId = id + "-" + i;
            FogDevice camera = addCamera(mobileId, userId, appId, router.getId()); // adding a smart camera to the physical topology. Smart cameras have been modeled as fog devices as well.
            camera.setUplinkLatency(2); // latency of connection between camera and router is 2 ms
            fogDevices.add(camera);
        }
        router.setParentId(parentId);
        return router;
    }

    private static FogDevice addCamera(String id, int userId, String appId, int parentId) {
        FogDevice camera = createFogDevice("m-" + id, 500, 1000, 10000, 10000, 3, 0, 87.53, 82.44);
        camera.setParentId(parentId);
        Sensor sensor = new Sensor("s-" + id, "CAMERA", userId, appId, new DeterministicDistribution(5)); // inter-transmission time of camera (sensor) follows a deterministic distribution
        sensors.add(sensor);
        Actuator ptz = new Actuator("ptz-" + id, userId, appId, "PTZ_CONTROL");
        actuators.add(ptz);
        sensor.setGatewayDeviceId(camera.getId());
        sensor.setLatency(1.0);  // latency of connection between camera (sensor) and the parent Smart Camera is 1 ms
        ptz.setGatewayDeviceId(camera.getId());
        ptz.setLatency(1.0);  // latency of connection between PTZ Control and the parent Smart Camera is 1 ms
        return camera;
    }

    /**
     * Creates a vanilla fog device
     *
     * @param nodeName    name of the device to be used in simulation
     * @param mips        MIPS
     * @param ram         RAM
     * @param upBw        uplink bandwidth
     * @param downBw      downlink bandwidth
     * @param level       hierarchy level of the device
     * @param ratePerMips cost rate per MIPS used
     * @param busyPower
     * @param idlePower
     * @return
     */
    private static FogDevice createFogDevice(String nodeName, long mips,
                                             int ram, long upBw, long downBw, int level, double ratePerMips, double busyPower, double idlePower) {

        List<Pe> peList = new ArrayList<Pe>();

        // 3. Create PEs and add these into a list.
        peList.add(new Pe(0, new PeProvisionerOverbooking(mips))); // need to store Pe id and MIPS Rating

        int hostId = FogUtils.generateEntityId();
        long storage = 1000000; // host storage
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

        List<Host> hostList = new ArrayList<Host>();
        hostList.add(host);

        String arch = "x86"; // system architecture
        String os = "Linux"; // operating system
        String vmm = "Xen";
        double time_zone = 10.0; // time zone this resource located
        double cost = 3.0; // the cost of using processing in this resource
        double costPerMem = 0.05; // the cost of using memory in this resource
        double costPerStorage = 0.001; // the cost of using storage in this
        // resource
        double costPerBw = 0.0; // the cost of using bw in this resource
        LinkedList<Storage> storageList = new LinkedList<Storage>(); // we are not adding SAN
        // devices by now

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

    /**
     * Function to create the Intelligent Surveillance application in the DDF model.
     *
     * @param appId  unique identifier of the application
     * @param userId identifier of the user of the application
     * @return
     */
    @SuppressWarnings({"serial"})
    private static Application createApplication(String appId, int userId) {

        Application application = Application.createApplication(appId, userId);
        /*
         * Adding modules (vertices) to the application model (directed graph)
         */
        application.addAppModule("object_detector", 10);
        application.addAppModule("motion_detector", 10);
        application.addAppModule("object_tracker", 10);
        application.addAppModule("user_interface", 10);

        /*
         * Connecting the application modules (vertices) in the application model (directed graph) with edges
         */
        application.addAppEdge("CAMERA", "motion_detector", 1000, 20000, "CAMERA", Tuple.UP, AppEdge.SENSOR); // adding edge from CAMERA (sensor) to Motion Detector module carrying tuples of type CAMERA
        application.addAppEdge("motion_detector", "object_detector", 2000, 2000, "MOTION_VIDEO_STREAM", Tuple.UP, AppEdge.MODULE); // adding edge from Motion Detector to Object Detector module carrying tuples of type MOTION_VIDEO_STREAM
        application.addAppEdge("object_detector", "user_interface", 500, 2000, "DETECTED_OBJECT", Tuple.UP, AppEdge.MODULE); // adding edge from Object Detector to User Interface module carrying tuples of type DETECTED_OBJECT
        application.addAppEdge("object_detector", "object_tracker", 1000, 100, "OBJECT_LOCATION", Tuple.UP, AppEdge.MODULE); // adding edge from Object Detector to Object Tracker module carrying tuples of type OBJECT_LOCATION
        application.addAppEdge("object_tracker", "PTZ_CONTROL", 100, 28, 100, "PTZ_PARAMS", Tuple.DOWN, AppEdge.ACTUATOR); // adding edge from Object Tracker to PTZ CONTROL (actuator) carrying tuples of type PTZ_PARAMS

        /*
         * Defining the input-output relationships (represented by selectivity) of the application modules.
         */
        application.addTupleMapping("motion_detector", "CAMERA", "MOTION_VIDEO_STREAM", new FractionalSelectivity(1.0)); // 1.0 tuples of type MOTION_VIDEO_STREAM are emitted by Motion Detector module per incoming tuple of type CAMERA
        application.addTupleMapping("object_detector", "MOTION_VIDEO_STREAM", "OBJECT_LOCATION", new FractionalSelectivity(1.0)); // 1.0 tuples of type OBJECT_LOCATION are emitted by Object Detector module per incoming tuple of type MOTION_VIDEO_STREAM
        application.addTupleMapping("object_detector", "MOTION_VIDEO_STREAM", "DETECTED_OBJECT", new FractionalSelectivity(0.05)); // 0.05 tuples of type MOTION_VIDEO_STREAM are emitted by Object Detector module per incoming tuple of type MOTION_VIDEO_STREAM

        /*
         * Defining application loops (maybe incomplete loops) to monitor the latency of.
         * Here, we add two loops for monitoring : Motion Detector -> Object Detector -> Object Tracker and Object Tracker -> PTZ Control
         */
        final AppLoop loop1 = new AppLoop(new ArrayList<String>() {{
            add("motion_detector");
            add("object_detector");
            add("object_tracker");
        }});
        final AppLoop loop2 = new AppLoop(new ArrayList<String>() {{
            add("object_tracker");
            add("PTZ_CONTROL");
        }});
        List<AppLoop> loops = new ArrayList<AppLoop>() {{
            add(loop1);
            add(loop2);
        }};

        application.setLoops(loops);
        return application;
    }
}