WITH heart_failure_admissions AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 59 AND 69
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND (
                (d.icd_version = 9 AND d.icd_code LIKE '428%')
                OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
            )
      )
),
cte_procedures AS (
    SELECT 
        c.hadm_id,
        COUNT(*) AS procedure_count
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
    WHERE di.label LIKE '%CT%' 
       OR di.label LIKE '%X-RAY%' 
       OR di.label LIKE '%XRAY%'
    GROUP BY c.hadm_id
),
los_and_icu AS (
    SELECT 
        hfa.hadm_id,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_use,
        COALESCE(cp.procedure_count, 0) AS procedure_count
    FROM heart_failure_admissions hfa
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON hfa.hadm_id = a.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON hfa.hadm_id = i.hadm_id
    LEFT JOIN cte_procedures cp ON hfa.hadm_id = cp.hadm_id
),
filtered_admissions AS (
    SELECT 
        los_days,
        icu_use,
        procedure_count,
        CASE 
            WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
            WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
        END AS los_category
    FROM los_and_icu
    WHERE los_days BETWEEN 1 AND 8
)
SELECT 
    los_category,
    icu_use,
    APPROX_QUANTILES(procedure_count, 4)[OFFSET(1)] AS p25,
    APPROX_QUANTILES(procedure_count, 4)[OFFSET(2)] AS p50,
    APPROX_QUANTILES(procedure_count, 4)[OFFSET(3)] AS p75
FROM filtered_admissions
GROUP BY los_category, icu_use;