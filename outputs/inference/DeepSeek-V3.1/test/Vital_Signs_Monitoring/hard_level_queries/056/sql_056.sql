WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        a.hadm_id,
        a.hospital_expire_flag,
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON a.hadm_id = ie.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 74 AND 84
        AND dd.icd_code LIKE 'I6[0-2]%'
        AND di.icd_version = 10
),
-- Get fever events (Temperature > 38.5) in first 48h
fever AS (
    SELECT 
        ce.stay_id,
        DATETIME_TRUNC(ce.charttime, HOUR) AS chart_hour
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE ce.itemid = 223762 -- Temperature Celsius
        AND ce.valuenum > 38.5
),
-- Get hypoxemia events (SpO2 < 90) in first 48h
hypoxemia AS (
    SELECT 
        ce.stay_id,
        DATETIME_TRUNC(ce.charttime, HOUR) AS chart_hour
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE ce.itemid = 220277 -- SpO2
        AND ce.valuenum < 90
),
-- Get tachypnea events (RR > 20) in first 48h
tachypnea AS (
    SELECT 
        ce.stay_id,
        DATETIME_TRUNC(ce.charttime, HOUR) AS chart_hour
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE ce.itemid = 220210 -- Respiratory Rate
        AND ce.valuenum > 20
),
-- Combine instability events and count distinct per type per stay
instability AS (
    SELECT 
        c.stay_id,
        COUNT(DISTINCT f.chart_hour) AS fever_hours,
        COUNT(DISTINCT h.chart_hour) AS hypoxemia_hours,
        COUNT(DISTINCT t.chart_hour) AS tachypnea_hours,
        COUNT(DISTINCT f.chart_hour) + 
        COUNT(DISTINCT h.chart_hour) + 
        COUNT(DISTINCT t.chart_hour) AS total_instability_hours
    FROM cohort c
    LEFT JOIN fever f
        ON c.stay_id = f.stay_id
            AND f.chart_hour BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    LEFT JOIN hypoxemia h
        ON c.stay_id = h.stay_id
            AND h.chart_hour BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    LEFT JOIN tachypnea t
        ON c.stay_id = t.stay_id
            AND t.chart_hour BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    GROUP BY c.stay_id
),
-- Compute the 90th percentile of total instability hours
percentile_val AS (
    SELECT 
        PERCENTILE_CONT(total_instability_hours, 0.9) OVER() AS p90
    FROM instability
    LIMIT 1
)
-- For the top decile (>=90th percentile), compute the required metrics
SELECT 
    COUNT(*) AS n,
    AVG(c.los) AS mean_icu_los,
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,
    AVG(i.fever_hours) AS mean_fever_hours,
    AVG(i.hypoxemia_hours) AS mean_hypoxemia_hours,
    AVG(i.tachypnea_hours) AS mean_tachypnea_hours
FROM cohort c
INNER JOIN instability i
    ON c.stay_id = i.stay_id
CROSS JOIN percentile_val p
WHERE i.total_instability_hours >= p.p90;