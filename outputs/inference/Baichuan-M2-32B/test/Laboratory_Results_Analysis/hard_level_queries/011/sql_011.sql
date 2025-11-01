WITH eligible_patients AS (
    SELECT subject_id, anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 47 AND 57
),
admissions_with_age AS (
    SELECT a.*, p.anchor_age AS age_at_anchor
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN eligible_patients p ON a.subject_id = p.subject_id
),
aki_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.icd_code LIKE 'N17%'
      AND d.icd_version = 10
),
admission_groups AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.anchor_age,
        CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_aki,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM admissions_with_age a
    LEFT JOIN aki_admissions aki ON a.hadm_id = aki.hadm_id
),
lab_instability AS (
    SELECT 
        a.hadm_id,
        COUNT(*) AS abnormal_lab_count
    FROM admission_groups a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
        ON a.hadm_id = l.hadm_id AND a.subject_id = l.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
        ON l.itemid = d.itemid
    WHERE 
        l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
        AND l.valuenum IS NOT NULL
        AND d.ref_range_lower IS NOT NULL
        AND d.ref_range_upper IS NOT NULL
        AND (l.valuenum < d.ref_range_lower OR l.valuenum > d.ref_range_upper)
    GROUP BY a.hadm_id
),
icu_indicator AS (
    SELECT 
        a.hadm_id,
        MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS has_icu_stay
    FROM admission_groups a
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON a.hadm_id = i.hadm_id AND a.subject_id = i.subject_id
    GROUP BY a.hadm_id
),
admission_metrics AS (
    SELECT 
        ag.hadm_id,
        ag.is_aki,
        ag.anchor_age,
        ag.hospital_expire_flag,
        TIMESTAMP_DIFF(ag.dischtime, ag.admittime, DAY) AS los,
        COALESCE(li.abnormal_lab_count, 0) AS abnormal_lab_count,
        ii.has_icu_stay
    FROM admission_groups ag
    LEFT JOIN lab_instability li ON ag.hadm_id = li.hadm_id
    LEFT JOIN icu_indicator ii ON ag.hadm_id = ii.hadm_id
),
final_groups AS (
    SELECT 
        is_aki,
        COUNT(*) AS num_admissions,
        AVG(los) AS avg_los,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
        AVG(abnormal_lab_count) AS mean_lab_instability_score,
        SUM(has_icu_stay) / COUNT(*) AS critical_event_frequency
    FROM admission_metrics
    GROUP BY is_aki
)
SELECT 
    is_aki,
    num_admissions,
    avg_los,
    mortality_rate,
    mean_lab_instability_score,
    critical_event_frequency
FROM final_groups
ORDER BY is_aki;