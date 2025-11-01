WITH cohort AS (
    SELECT DISTINCT
        a.hadm_id,
        a.admittime,
        a.dod,
        i.stay_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 68 AND 78
      AND (
          (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
      )
),
aki_diagnosis AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (icd_version = 9 AND icd_code LIKE '584%')
       OR (icd_version = 10 AND icd_code LIKE 'N17%')
),
ards_diagnosis AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (icd_version = 9 AND icd_code = '51882')
       OR (icd_version = 10 AND icd_code = 'J80')
),
apache_scores AS (
    SELECT 
        c.stay_id,
        c.value AS apache_score
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    WHERE c.itemid = 223924
),
deaths AS (
    SELECT 
        DATETIME_DIFF(TIMESTAMP(dod), admittime, DAY) AS time_to_death
    FROM cohort
    WHERE dod IS NOT NULL
),
aki_count AS (
    SELECT COUNT(DISTINCT hadm_id) AS num_aki
    FROM aki_diagnosis
    WHERE hadm_id IN (SELECT hadm_id FROM cohort)
),
ards_count AS (
    SELECT COUNT(DISTINCT hadm_id) AS num_ards
    FROM ards_diagnosis
    WHERE hadm_id IN (SELECT hadm_id FROM cohort)
),
apache_percentiles AS (
    SELECT 
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY apache_score) AS p25,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY apache_score) AS p50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY apache_score) AS p75
    FROM apache_scores
    WHERE stay_id IN (SELECT stay_id FROM cohort)
),
median_survival AS (
    SELECT PERCENTILE_CONT(time_to_death, 0.5) AS median
    FROM deaths
)
SELECT 
    (SELECT COUNT(*) FROM cohort) AS cohort_size,
    (SELECT COUNTIF(dod <= admittime + INTERVAL '30 days') FROM cohort) AS num_dead_30d,
    aki_count.num_aki,
    ards_count.num_ards,
    apache_percentiles.p25,
    apache_percentiles.p50,
    apache_percentiles.p75,
    median_survival.median
FROM aki_count, ards_count, apache_percentiles, median_survival;