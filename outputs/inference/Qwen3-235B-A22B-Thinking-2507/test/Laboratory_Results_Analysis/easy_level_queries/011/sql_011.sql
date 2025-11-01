WITH icu_stays_56m AS (
    SELECT 
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON icu.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND EXTRACT(YEAR FROM icu.intime) - (pat.anchor_year - pat.anchor_age) = 56
),
potassium AS (
    SELECT 
        icu.stay_id,
        le.valuenum AS potassium_value
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
        ON le.itemid = dlab.itemid
    INNER JOIN icu_stays_56m icu
        ON le.hadm_id = icu.hadm_id
        AND le.charttime >= icu.intime
        AND le.charttime <= icu.outtime
    WHERE dlab.label = 'Potassium'
        AND dlab.fluid = 'Blood'
        AND le.valuenum IS NOT NULL
),
peaks AS (
    SELECT 
        stay_id,
        MAX(potassium_value) AS peak_potassium
    FROM potassium
    GROUP BY stay_id
)
SELECT STDDEV(peak_potassium) AS std_dev_peak_potassium
FROM peaks;