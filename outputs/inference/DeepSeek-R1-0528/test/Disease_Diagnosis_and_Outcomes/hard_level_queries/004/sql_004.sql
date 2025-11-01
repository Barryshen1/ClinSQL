WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender,
        p.anchor_age,
        p.anchor_year,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
),
ich_diagnoses AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        icd_version = 10 
        AND icd_code LIKE 'I61%'
),
cohort_ich AS (
    SELECT c.*
    FROM cohort c
    INNER JOIN ich_diagnoses d
        ON c.hadm_id = d.hadm_id
),
icu_stays AS (
    SELECT 
        subject_id,
        hadm_id,
        stay_id,
        intime,
        outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE hadm_id IN (SELECT hadm_id FROM cohort_ich)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) = 1
),
gcs_first AS (
    SELECT 
        ce.stay_id,
        ce.valuenum AS gcs
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN icu_stays i
        ON ce.stay_id = i.stay_id
    WHERE 
        ce.itemid = 198  -- GCS total
        AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) = 1
),
complications_flags AS (
    SELECT 
        hadm_id,
        MAX(CASE WHEN icd_code IN ('I61.5', 'I61.6', 'I61.8', 'I62.0') THEN 1 ELSE 0 END) AS intraventricular,
        MAX(CASE WHEN icd_code IN ('I61.3', 'I61.4') THEN 1 ELSE 0 END) AS infratentorial
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE hadm_id IN (SELECT hadm_id FROM cohort_ich)
    GROUP BY hadm_id
),
risk_data AS (
    SELECT 
        c.hadm_id,
        c.hospital_expire_flag,
        c.admittime,
        c.dischtime,
        g.gcs,
        COALESCE(cf.intraventricular, 0) AS intraventricular,
        COALESCE(cf.infratentorial, 0) AS infratentorial,
        CASE 
            WHEN g.gcs BETWEEN 3 AND 4 THEN 2
            WHEN g.gcs BETWEEN 5 AND 12 THEN 1
            ELSE 0 
        END AS gcs_points,
        COALESCE(cf.intraventricular, 0) + COALESCE(cf.infratentorial, 0) AS location_points,
        CASE 
            WHEN g.gcs BETWEEN 3 AND 4 THEN 2
            WHEN g.gcs BETWEEN 5 AND 12 THEN 1
            ELSE 0 
        END + COALESCE(cf.intraventricular, 0) + COALESCE(cf.infratentorial, 0) AS risk_score
    FROM cohort_ich c
    INNER JOIN icu_stays i
        ON c.hadm_id = i.hadm_id
    INNER JOIN gcs_first g
        ON i.stay_id = g.stay_id
    LEFT JOIN complications_flags cf
        ON c.hadm_id = cf.hadm_id
),
risk_quartiles AS (
    SELECT 
        hadm_id,
        NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
    FROM risk_data
)
SELECT 
    rq.risk_quartile,
    COUNT(*) AS patient_count,
    SUM(r.hospital_expire_flag) AS in_hospital_deaths,
    ROUND(AVG(r.hospital_expire_flag) * 100, 2) AS mortality_rate_percent,
    COUNT(CASE WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` cc 
        WHERE 
            cc.hadm_id = r.hadm_id 
            AND cc.icd_version = 10 
            AND (cc.icd_code LIKE 'I21%' OR cc.icd_code LIKE 'I22%' OR cc.icd_code LIKE 'I46%' OR cc.icd_code LIKE 'I50%')
    ) THEN 1 END) AS cardiac_complication_count,
    ROUND(COUNT(CASE WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` cc 
        WHERE 
            cc.hadm_id = r.hadm_id 
            AND cc.icd_version = 10 
            AND (cc.icd_code LIKE 'I21%' OR cc.icd_code LIKE 'I22%' OR cc.icd_code LIKE 'I46%' OR cc.icd_code LIKE 'I50%')
    ) THEN 1 END) / COUNT(*) * 100, 2) AS cardiac_complication_rate_percent,
    COUNT(CASE WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` nc 
        WHERE 
            nc.hadm_id = r.hadm_id 
            AND nc.icd_version = 10 
            AND (nc.icd_code LIKE 'G93.6%' OR nc.icd_code LIKE 'G40%' OR nc.icd_code LIKE 'R56%' OR nc.icd_code LIKE 'G91%' OR nc.icd_code LIKE 'I63%')
    ) THEN 1 END) AS neurologic_complication_count,
    ROUND(COUNT(CASE WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` nc 
        WHERE 
            nc.hadm_id = r.hadm_id 
            AND nc.icd_version = 10 
            AND (nc.icd_code LIKE 'G93.6%' OR nc.icd_code LIKE 'G40%' OR nc.icd_code LIKE 'R56%' OR nc.icd_code LIKE 'G91%' OR nc.icd_code LIKE 'I63%')
    ) THEN 1 END) / COUNT(*) * 100, 2) AS neurologic_complication_rate_percent,
    APPROX_QUANTILES(
        CASE WHEN r.hospital_expire_flag = 0 THEN DATE_DIFF(r.dischtime, r.admittime, DAY) END, 
        100
    )[SAFE_OFFSET(50)] AS median_los_survivors_days
FROM risk_data r
INNER JOIN risk_quartiles rq
    ON r.hadm_id = rq.hadm_id
GROUP BY rq.risk_quartile
ORDER BY rq.risk_quartile;