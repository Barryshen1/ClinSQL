WITH cohort_diagnoses AS (
    SELECT di.subject_id, di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE d.long_title LIKE '%acute respiratory failure%'
),
cohort_patients AS (
    SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, p.anchor_age
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    JOIN cohort_diagnoses cd
        ON i.subject_id = cd.subject_id AND i.hadm_id = cd.hadm_id
    WHERE p.anchor_age BETWEEN 43 AND 53
),
cohort_vitals AS (
    SELECT cp.stay_id, cp.intime,
        SUM(CASE WHEN ce.itemid = 51 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
        SUM(CASE WHEN ce.itemid = 211 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high_count,
        SUM(CASE WHEN ce.itemid = 51 AND ce.valuenum < 65 THEN 1 ELSE 0 END) +
        SUM(CASE WHEN ce.itemid = 211 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS instability_index
    FROM cohort_patients cp
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cp.stay_id = ce.stay_id
    WHERE ce.charttime BETWEEN cp.intime AND TIMESTAMP_ADD(cp.intime, INTERVAL 48 HOUR)
    GROUP BY cp.stay_id, cp.intime
),
cohort_index AS (
    SELECT stay_id, instability_index
    FROM cohort_vitals
),
cohort_percentiles AS (
    SELECT
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY instability_index) AS p95,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY instability_index) AS p75
    FROM cohort_index
),
top_quartile AS (
    SELECT ci.stay_id
    FROM cohort_index ci
    CROSS JOIN cohort_percentiles cp
    WHERE ci.instability_index >= cp.p75
),
top_quartile_metrics AS (
    SELECT
        SUM(CASE WHEN ce.itemid = 51 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS top_map_low_count,
        SUM(CASE WHEN ce.itemid = 211 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS top_hr_high_count,
        AVG(i.los) AS top_los,
        AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS top_mortality
    FROM top_quartile tq
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON tq.stay_id = i.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON tq.stay_id = ce.stay_id
        AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
),
general_population_metrics AS (
    SELECT
        SUM(CASE WHEN ce.itemid = 51 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS gen_map_low_count,
        SUM(CASE WHEN ce.itemid = 211 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS gen_hr_high_count,
        AVG(i.los) AS gen_los,
        AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS gen_mortality
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON i.stay_id = ce.stay_id
        AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
)
SELECT
    cp.p95,
    t.top_map_low_count,
    t.top_hr_high_count,
    t.top_los,
    t.top_mortality,
    g.gen_map_low_count,
    g.gen_hr_high_count,
    g.gen_los,
    g.gen_mortality
FROM cohort_percentiles cp
CROSS JOIN top_quartile_metrics t
CROSS JOIN general_population_metrics g;