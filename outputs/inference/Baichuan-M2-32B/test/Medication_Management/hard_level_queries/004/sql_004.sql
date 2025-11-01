WITH stroke_patients AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        COUNT(DISTINCT d.seq_num) AS complexity_score
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 48 AND 58
        AND d.icd_code LIKE 'I63.%'
        AND d.icd_version = 10
    GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
stroke_patients_with_percentile AS (
    SELECT 
        *,
        PERCENT_RANK() OVER (ORDER BY complexity_score) AS complexity_percentile
    FROM stroke_patients
),
cyp3a4_drugs AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`  -- Fixed: added full dataset path
    WHERE drug IN (
        'simvastatin', 'ketoconazole', 'clarithromycin', 'erythromycin', 
        'verapamil', 'diltiazem', 'rifampin', 'grapefruit juice'
    )
    AND EXISTS (
        SELECT 1
        FROM stroke_patients s
        WHERE s.hadm_id = prescriptions.hadm_id
            AND prescriptions.starttime BETWEEN s.admittime AND s.dischtime
    )
),
final_cohort AS (
    SELECT 
        sp.*,
        CASE WHEN c.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_cyp3a4_drug
    FROM stroke_patients_with_percentile sp
    LEFT JOIN cyp3a4_drugs c 
        ON sp.subject_id = c.subject_id AND sp.hadm_id = c.hadm_id
),
comparison_results AS (
    SELECT 
        has_cyp3a4_drug,
        AVG(complexity_score) AS avg_complexity_score,
        AVG(complexity_percentile) AS avg_complexity_percentile,
        AVG(los_days) AS avg_los_days,
        AVG(CAST(hospital_expire_flag AS FLOAT)) * 100 AS mortality_rate_percent
    FROM final_cohort
    GROUP BY has_cyp3a4_drug
),
top_quartile AS (
    SELECT 
        AVG(los_days) AS avg_los_days_top_quartile,
        AVG(CAST(hospital_expire_flag AS FLOAT)) * 100 AS mortality_rate_percent_top_quartile
    FROM final_cohort
    WHERE complexity_percentile >= 0.75
)
SELECT 
    'Comparison' AS result_type,
    has_cyp3a4_drug AS group_flag,
    avg_complexity_score,
    avg_complexity_percentile,
    avg_los_days,
    mortality_rate_percent
FROM comparison_results
UNION ALL
SELECT 
    'Top Quartile' AS result_type,
    NULL AS group_flag,
    NULL AS avg_complexity_score,
    NULL AS avg_complexity_percentile,
    avg_los_days_top_quartile AS avg_los_days,
    mortality_rate_percent_top_quartile AS mortality_rate_percent
FROM top_quartile;