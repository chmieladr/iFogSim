%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Bachelor's & Master's report Template             %%
%% Copyleft by Artur M. Brodzki & Piotr Woźniak      %%
%% Covered for Lab/Assigment report by Tymon Żarski  %%
%% Faculty of Electronics and Information Technology %%
%% Warsaw University of Technology, 2019-2020        %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\ProvidesClass{eiti/eiti-report}

%--------------------------------------
% Define class parameters
%--------------------------------------
\RequirePackage{kvoptions}
\SetupKeyvalOptions{
    family=eiti/eiti-report.cls,
    prefix=eiti
}

\DeclareStringOption[2.5cm]{left}
\DeclareStringOption[2.5cm]{right}
\DeclareStringOption[2.5cm]{top}
\DeclareStringOption[2.5cm]{bottom}
\DeclareStringOption[6mm]{bindingoffset}
\DeclareBoolOption[false]{nohyphenation}
\DeclareBoolOption[false]{fast}
\DeclareBoolOption[false]{oneside}
\ProcessKeyvalOptions*

\ifeitioneside
    \LoadClass[12pt,oneside]{mwart}
\else
    \LoadClass[12pt,twoside]{mwart}
\fi

%--------------------------------
% Engine detection (before encoding and biblatex)
%--------------------------------
\RequirePackage{ifpdf}
\RequirePackage{ifluatex}
\RequirePackage{ifxetex}

%--------------------------------
% Encoding (must load before biblatex)
%--------------------------------
\ifpdf
    \RequirePackage[T1]{fontenc}
    \RequirePackage[utf8]{inputenc}
\fi
\ifluatex
    \RequirePackage[T1]{fontenc}
    \RequirePackage[utf8]{luainputenc}
\fi

%--------------------------------
% Common packages
%--------------------------------
\RequirePackage{pdftexcmds}
\RequirePackage{amsmath}    % Basic mathematical typesetting
\RequirePackage{amssymb}    % Advanced math symbols
\RequirePackage{amsthm}     % Theorems typesetting
\RequirePackage{array}      % Advanced table column formats
\ifeitifast
    \RequirePackage[            % Bibliography in biber
        backend=biber,
        style=ieee,
        dashed=false
    ]{biblatex}
\else
    \RequirePackage[            % Bibliography in biber
        backend=biber,
        style=ieee
    ]{biblatex}
\fi
\RequirePackage[            % Custom figure and table captions
    font=small,
    labelfont=bf,
    labelsep=period,
    compatibility=false
]{caption}
\RequirePackage{chngcntr}   % Per-section counters
\RequirePackage{enumitem}   % Itemize/enumrate
\RequirePackage{fancyhdr}   % Custom header/footer styles
\ifeitifast
    \RequirePackage{lmodern}
\else
    \RequirePackage{fourier}    % Adobe Utopia font
\fi
\ifeitifast
    \RequirePackage[draft]{graphicx}
\else
    \RequirePackage{graphicx}   % Enhanced images support
\fi
\RequirePackage{multirow}   % Advanced table cells
\RequirePackage{setspace}   % Set space between lines
\RequirePackage{scrextend}  % Allows \addmargin environment
\RequirePackage{tocloft}    % Custom ToC/LoF/LoT
\RequirePackage{url}        % URL-sensitive line breaks
\RequirePackage{xkeyval}    % Keys and class parameters
\RequirePackage{xspace}     % Remove duplicated spaces

%--------------------------------------
% PdfTeX specific configuration
%--------------------------------------
\ifpdf
    \ifeitifast
        \RequirePackage[
            protrusion=false,
            expansion=false
        ]{microtype}
    \else
        \RequirePackage[
            protrusion=true,
            expansion=false
        ]{microtype}
    \fi
\fi

%--------------------------------------
% XeTeX specific configuration
%--------------------------------------
\ifxetex
    \RequirePackage{fontspec-xetex}
    \RequirePackage[
        protrusion=true,
    ]{microtype}
\fi

%--------------------------------------
% LuaTeX specific configuration
%--------------------------------------
\ifluatex
    \ifeitifast\else
        \RequirePackage{luatexbase}
        \RequirePackage{luacode}
        % In LuaTeX, we can prevent one-letter words
        % from beging at the end of the line.
        \begin{luacode}
        local debug = false
        local glyph_id = node.id "glyph"
        local glue_id  = node.id "glue"
        local hlist_id = node.id "hlist"

        local prevent_single_letter = function (head)
            while head do
                if head.id == glyph_id then
                    if unicode.utf8.match(unicode.utf8.char(head.char),"%a") then     -- is a letter
                        if head.prev.id == glue_id and head.next.id == glue_id then   -- is one letter word

                            local p = node.new("penalty")
                            p.penalty = 10000

                            if debug then
                                local w = node.new("whatsit","pdf_literal")
                                w.data = "q 1 0 1 RG 1 0 1 rg 0 0 m 0 5 l 2 5 l 2 0 l b Q"
                                node.insert_after(head,head,w)
                                node.insert_after(head,w,p)
                            else
                                node.insert_after(head,head,p)
                            end
                        end
                    end
                end
                head = head.next
            end
            return true
        end

        luatexbase.add_to_callback("pre_linebreak_filter",prevent_single_letter,"~")

        \end{luacode}
    \fi
    \ifeitifast
        \RequirePackage[
            protrusion=false,
            expansion=false
        ]{microtype}
    \else
        \RequirePackage[
            protrusion=true,
            expansion=false
        ]{microtype}
    \fi
\fi

%--------------------------------
% Produce clickable hyperlinks
% in ToC, LoF and LoT
%--------------------------------
\RequirePackage{hyperref}
\hypersetup{
    colorlinks,
    citecolor=black,
    filecolor=black,
    linkcolor=black,
    urlcolor=black
}

%--------------------------------------
% Default margin is 2.5 cm
%--------------------------------------
\RequirePackage[
    a4paper,
    left=\eitileft,
    right=\eitiright,
    top=\eititop,
    bottom=\eitibottom,
    bindingoffset=\eitibindingoffset
]{geometry}

%--------------------------------
% Turn off hyphenation
%--------------------------------
\ifeitinohyphenation
    \tolerance=1
    \emergencystretch=\maxdimen
    \hyphenpenalty=10000
    \hbadness=10000
\fi

%--------------------------------
% Initial setup
%--------------------------------
\setstretch{1.2}
\raggedbottom
\setlength{\textfloatsep}{10pt plus 2pt minus 2pt}
\setlength{\intextsep}{10pt plus 2pt minus 2pt}
\counterwithin{figure}{section}
\counterwithin{table}{section}

%--------------------------------
% Table of Contents setup
%--------------------------------
\setlength{\cftbeforesecskip}{2pt}
\renewcommand{\cftsecfont}{\bf\normalsize}
\renewcommand{\cftsecpagefont}{\normalfont}
\renewcommand{\cftsecleader}{\cftdotfill{\cftsecdotsep}}
\renewcommand{\cftsecdotsep}{\cftdotsep}

%--------------------------------
% List of Figures setup
%--------------------------------
\renewcommand*\l@figure{\@dottedtocline{1}{0.5em}{2.25em}}
\newcommand{\listoffigurestoc}{
    \listoffigures
    \addcontentsline{toc}{section}{\listfigurename}
}

%--------------------------------
% List of Tables setup
%--------------------------------
\renewcommand*\l@table{\@dottedtocline{1}{0.5em}{2.25em}}
\newcommand{\listoftablestoc}{
    \listoftables
    \addcontentsline{toc}{section}{\listtablename}
}

%--------------------------------
% Header & footer
%--------------------------------
\SetSectionFormatting{section}{0.5cm}{\FormatHangHeading{\Large}}{0.5cm}
\let\oldsection\section
\renewcommand{\section}{
	\thispagestyle{plain}
	\oldsection
}

\fancypagestyle{plain}{
	\fancyhf{}
	\renewcommand{\headrulewidth}{0pt}
	\fancyfoot[LE,RO]{\thepage}
}

\fancypagestyle{headings}{
	\fancyhead{}
	\renewcommand{\headrulewidth}{1pt}
	\fancyheadoffset{0cm}
	\fancyhead[RO]{\nouppercase{\thesection.\hspace{8pt}\leftmark}}
	\fancyhead[LE]{\nouppercase{\thesection.\hspace{8pt}\leftmark}}
	\fancyfoot{}
	\fancyfoot[LE,RO]{\thepage}
}
\pagestyle{headings}

\renewcommand{\sectionmark}[1]{
	\markboth{#1}{#1}
}

%--------------------------------
% Set default list style
%--------------------------------
\setlist[itemize,1]{topsep=2pt,label=\large$\bullet$, leftmargin=28pt}
\setlist[itemize,2]{topsep=2pt,leftmargin=18pt}
\setlist[itemize,3]{topsep=2pt,leftmargin=18pt}

\setlist[enumerate,1]{topsep=2pt,leftmargin=24pt}
\setlist[enumerate,2]{topsep=2pt,leftmargin=16pt}
\setlist[enumerate,3]{topsep=2pt,leftmargin=16pt}

%--------------------------------
% Wybór języka pracy
%--------------------------------
\newcommand{\langpol}{
    \newcommand{\@lang}{polish}
    \usepackage[polish]{babel}
    \usepackage{csquotes}

	\newtheorem{theorem}{Twierdzenie}
	\newtheorem{lemma}{Lemat}
	\newtheorem{corollary}{Wniosek}
	\newtheorem{definition}{Definicja}
	\newtheorem{axiom}{Aksjomat}
	\newtheorem{assumption}{Założenie}

	\AtBeginDocument{
		\renewcommand{\listfigurename}{Spis rysunków}
		\renewcommand{\listtablename}{Spis tabel}
		\renewcommand{\tablename}{Tabela}
	}
}
\newcommand{\langeng}{
    \newcommand{\@lang}{english}
    \usepackage[english]{babel}
    \usepackage{csquotes}

	\newtheorem{theorem}{Theorem}
	\newtheorem{lemma}{Lemma}
	\newtheorem{corollary}{Corollary}
	\newtheorem{definition}{Definition}
	\newtheorem{axiom}{Axiom}
	\newtheorem{assumption}{Assumption}

	\AtBeginDocument{
		\renewcommand{\listfigurename}{List of Figures}
		\renewcommand{\listtablename}{List of Tables}
		\renewcommand{\tablename}{Table}
	}
}

%--------------------------------
% Strona tytułowa - makra
%--------------------------------

\providecommand{\@reportDescription}{}
\newcommand{\reportDescription}[1]{
    \renewcommand{\@reportDescription}{#1}
}
\newcommand{\instytut}[1]{
    \newcommand{\@instytut}{#1}
}
\newcommand{\przedmiot}[1]{
    \newcommand{\@przedmiot}{#1}
}
\newcommand{\specjalnosc}[1]{
    \newcommand{\@specjalnosc}{#1}
}
\newcommand{\album}[1]{
    \newcommand{\@album}{#1}
}
\newcommand{\prowadzacy}[1]{
    \newcommand{\@prowadzacy}{#1}
}


%--------------------------------
% Strona tytułowa
%--------------------------------
\let\oldmaketitle\maketitle
\renewcommand{\maketitle}{
    \linespread{1.15}

    \thispagestyle{empty}
    \pagenumbering{gobble}

    \begin{center}

        \ifnum \pdf@strcmp{\@lang}{polish} = 0
           {\large przedmiot \\ \@przedmiot} \\
        \fi
        \ifnum \pdf@strcmp{\@lang}{english} = 0
            {\large course \\ \@przedmiot} \\
        \fi
        \hfill \break

        \@title \\
        \ifnum \pdf@strcmp{\@lang}{polish} = 0
            \ifx\@reportDescription\empty\else
                {\normalsize \@reportDescription} \\
            \fi
        \fi
        \ifnum \pdf@strcmp{\@lang}{english} = 0
            \ifx\@reportDescription\empty\else
                {\normalsize \@reportDescription} \\
            \fi
        \fi
        \hfill \break
        \LARGE
        \@author \\
        \normalsize
        \ifnum \pdf@strcmp{\@lang}{english} = 0
            WARSAW \@date
        \fi
    \end{center}

    \pagenumbering{arabic}
    \setcounter{page}{1}
}

%--------------------------------
% Spis załączników - makra
%--------------------------------
\newcommand{\nocontentsline}[3]{}
\newcommand{\tocless}[2]{%
    \bgroup\let\addcontentsline=\nocontentsline#1{#2}\egroup
}

\newcommand{\@appendixtitle}{
    \ifnum \pdf@strcmp{\@lang}{polish} = 0
        Załącznik
    \fi
    \ifnum \pdf@strcmp{\@lang}{english} = 0
        Appendix
    \fi
}

\let\standardappendix\appendix
\renewcommand\appendix[1]{%
    \tocless\section{\hspace*{1.5em} #1}
    \addcontentsline{app}{subsection}{\hspace*{-1.1em}\arabic{section}.\hspace*{0.5em} #1}
}

\newcommand\listofappendicestoc{
    \ifnum \pdf@strcmp{\@lang}{polish} = 0
        \section*{Spis załączników}\@starttoc{app}
    \fi
    \ifnum \pdf@strcmp{\@lang}{english} = 0
        \section*{List of Appendices}\@starttoc{app}
    \fi

    \standardappendix
    \renewcommand{\thesection}{\@appendixtitle~\arabic{section}}
}

\newcommand{\makeauthorship}{
    \ifnum \pdf@strcmp{\@lang}{polish} = 0
        \thispagestyle{plain}
        \begin{figure}[ht]
            \vspace{-55pt}
            \noindent\makebox[\textwidth]{
            \includegraphics[width=1.19\textwidth]{eiti/oswiadczenie_autora_pracy.pdf}
            }
        \end{figure}
    \fi
    \ifnum \pdf@strcmp{\@lang}{english} = 0
        \thispagestyle{plain}
        \begin{figure}[ht]
            \vspace{-55pt}
            \noindent\makebox[\textwidth]{
            \includegraphics[width=1.19\textwidth]{eiti/thesis_author_declaration-1.pdf}
            }
        \end{figure}
        \newpage
        \thispagestyle{plain}
        \begin{figure}[h]
            \vspace{-55pt}
            \noindent\makebox[\textwidth]{
            \includegraphics[width=1.19\textwidth]{eiti/thesis_author_declaration-2.pdf}
            }
        \end{figure}
    \fi
}
