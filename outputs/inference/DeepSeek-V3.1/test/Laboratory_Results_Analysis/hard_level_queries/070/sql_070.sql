WITH hemorrhagic_stroke_cohort AS (
    SELECT DISTINCT
        p.subject_id, 
        p.anchor_age,
        a.hadm_id, 
        a.admittime, 
        COALESCE(a.dischtime, i.outtime) AS dischtime,
        a.hospital_expire_flag,
        DATETIME_DIFF(COALESCE(a.dischtime, i.outtime), a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 40 AND 50
        AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%')
        AND di.icd_version = 10
        AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
),

cohort_labs AS (
    SELECT 
        hc.subject_id,
        hc.hadm_id,
        le.itemid,
        le.flag
    FROM hemorrhagic_stroke_cohort hc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON hc.hadm_id = le.hadm_id
        AND le.charttime BETWEEN hc.admittime AND DATETIME_ADD(hc.admittime, INTERVAL 72 HOUR)
    WHERE le.flag IS NOT NULL 
        AND le.flag != 'normal'
        AND le.flag != ''
),

cohort_score AS (
    SELECT 
        subject_id,
        hadm_id,
        COUNT(DISTINCT itemid) AS lab_instability_score
    FROM cohort_labs
    GROUP BY subject_id, hadm_id
),

cohort_with_score AS (
    SELECT 
        hc.*,
        COALESCE(cs.lab_instability_score, 0) AS lab_instability_score
    FROM hemorrhagic_stroke_cohort hc
    LEFT JOIN cohort_score cs
        ON hc.hadm_id = cs.hadm_id AND hc.subject_id = cs.subject_id
),

cohort_quartiles AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile
    FROM cohort_with_score
),

general_inpatients AS (
    SELECT DISTINCT
        a.hadm_id,
        a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.anchor_age >= 18
        AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
),

general_labs AS (
    SELECT 
        gi.hadm_id,
        le.itemid,
        le.flag
    FROM general_inpatients gi
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON gi.hadm_id = le.hadm_id
        AND le.charttime BETWEEN gi.admittime AND DATETIME_ADD(gi.admittime, INTERVAL 72 HOUR)
),

general_abnormal_rates AS (
    SELECT 
        itemid,
        COUNT(*) AS total_measurements,
        SUM(CASE WHEN flag IS NOT NULL AND flag != 'normal' AND flag != '' THEN 1 ELSE 0 END) AS abnormal_measurements,
        SAFE_DIVIDE(SUM(CASE WHEN flag IS NOT NULL AND flag != 'normal' AND flag != '' THEN 1 ELSE 0 END), COUNT(*)) AS abnormal_rate
    FROM general_labs
    GROUP BY itemid
),

cohort_abnormal_rates AS (
    SELECT 
        itemid,
        COUNT(*) AS total_measurements,
        SUM(CASE WHEN flag IS NOT NULL AND flag != 'normal' AND flag != '' THEN 1 ELSE 0 END) AS abnormal_measurements,
        SAFE_DIVIDE(SUM(CASE WHEN flag IS NOT NULL AND flag != 'normal' AND flag != '' THEN 1 ELSE 0 END), COUNT(*)) AS abnormal_rate
    FROM cohort_labs
    GROUP BY itemid
),

quartile_summary AS (
    SELECT 
        'quartile' AS result_type,
        CAST(cq.quartile AS STRING) AS quartile,
        CAST(COUNT(*) AS STRING) AS num_patients,
        CAST(AVG(cq.lab_instability_score) AS STRING) AS avg_score,
        CAST(AVG(cq.los_days) AS STRING) AS avg_los,
        CAST(SAFE_DIVIDE(SUM(cq.hospital_expire_flag), COUNT(*)) AS STRING) AS mortality_rate,
        NULL AS itemid,
        NULL AS lab_name,
        NULL AS cohort_total,
        NULL AS cohort_abnormal,
        NULL AS cohort_abnormal_rate,
        NULL AS general_total,
        NULL AS general_abnormal,
        NULL AS general_abnormal_rate
    FROM cohort_quartiles cq
    GROUP BY cq.quartile
),

lab_rates AS (
    SELECT 
        'lab' AS result_type,
        NULL AS quartile,
        NULL AS num_patients,
        NULL AS avg_score,
        NULL AS avg_los,
        NULL AS mortality_rate,
        CAST(car.itemid AS STRING) AS itemid,
        dli.label AS lab_name,
        CAST(car.total_measurements AS STRING) AS cohort_total,
        CAST(car.abnormal_measurements AS STRING) AS cohort_abnormal,
        CAST(car.abnormal_rate AS STRING) AS cohort_abnormal_rate,
        CAST(gar.total_measurements AS STRING) AS general_total,
        CAST(gar.abnormal_measurements AS STRING) AS general_abnormal,
        CAST(gar.abnormal_rate AS STRING) AS general_abnormal_rate
    FROM cohort_abnormal_rates car
    INNER JOIN general_abnormal_rates gar
        ON car.itemid = gar.itemid
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON car.itemid = dli.itemid
    WHERE car.total_measurements > 10
)

SELECT * FROM quartile_summary
UNION ALL
SELECT * FROM lab_rates
ORDER BY result_type, quartile, cohort_abnormal_rate DESC;