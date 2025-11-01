WITH multi_trauma_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code
    AND d.icd_version = dic.icd_version
  WHERE dic.long_title IS NOT NULL
    AND (
      (
        LOWER(dic.long_title) LIKE '%multiple%' 
        AND (
          LOWER(dic.long_title) LIKE '%injur%' 
          OR LOWER(dic.long_title) LIKE '%trauma%'
          OR LOWER(dic.long_title) LIKE '%traumatic%'
        )
      )
      OR LOWER(dic.long_title) LIKE '%polytrauma%'
    )
),

cohort_admissions AS (
  SELECT a.*
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.hadm_id IN (SELECT hadm_id FROM multi_trauma_hadm)
),

first24_meds AS (
  SELECT
    ca.hadm_id,
    ca.subject_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    COUNT(DISTINCT LOWER(TRIM(p.drug))) AS med_count,
    MAX(
      CASE
        WHEN p.drug IS NOT NULL
         AND REGEXP_CONTAINS(LOWER(p.drug),
           r'(sertraline|fluoxetine|paroxetine|citalopram|escitalopram|venlafaxine|duloxetine|tramadol|linezolid|meperidine|methadone|buspirone|mirtazapine)'
         )
        THEN 1 ELSE 0
      END
    ) AS serotonergic_flag
  FROM cohort_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = ca.hadm_id
    AND p.starttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 24 HOUR)
  GROUP BY ca.hadm_id, ca.subject_id, ca.admittime, ca.dischtime, ca.hospital_expire_flag
),

patient_metrics AS (
  SELECT
    ca.hadm_id,
    ca.subject_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    COALESCE(f24.med_count, 0) AS med_count,
    COALESCE(f24.serotonergic_flag, 0) = 1 AS serotonergic_exposure,
    SAFE_DIVIDE(TIMESTAMP_DIFF(ca.dischtime, ca.admittime, MINUTE), 1440.0) AS los_days
  FROM cohort_admissions ca
  LEFT JOIN first24_meds f24
    ON ca.hadm_id = f24.hadm_id
),

patient_metrics_with_rank AS (
  SELECT
    pm.*,
    PERCENT_RANK() OVER (ORDER BY med_count) AS complexity_percentile,
    NTILE(4) OVER (ORDER BY med_count) AS complexity_quartile
  FROM patient_metrics pm
),

quartile_cutpoints AS (
  SELECT
    q[OFFSET(1)] AS q25,
    q[OFFSET(2)] AS q50,
    q[OFFSET(3)] AS q75
  FROM (
    SELECT APPROX_QUANTILES(med_count, 4) AS q
    FROM patient_metrics_with_rank
  )
)

SELECT
  'quartile_cutpoints' AS group_label,
  CAST(NULL AS STRING) AS group_subgroup,
  CAST(NULL AS INT64) AS n_patients,
  CAST(NULL AS FLOAT64) AS mean_med_count,
  CAST(NULL AS FLOAT64) AS avg_complexity_percentile,
  CAST(qc.q25 AS FLOAT64) AS q25_med_count,
  CAST(qc.q50 AS FLOAT64) AS q50_med_count,
  CAST(qc.q75 AS FLOAT64) AS q75_med_count,
  CAST(NULL AS FLOAT64) AS mean_los_days,
  CAST(NULL AS FLOAT64) AS median_los_days,
  CAST(NULL AS FLOAT64) AS mortality_rate
FROM quartile_cutpoints qc

UNION ALL

SELECT
  CASE WHEN serotonergic_exposure THEN 'serotonergic' ELSE 'other' END AS group_label,
  'serotonergic_vs_other' AS group_subgroup,
  COUNT(*) AS n_patients,
  ROUND(AVG(med_count),2) AS mean_med_count,
  ROUND(AVG(complexity_percentile),3) AS avg_complexity_percentile,
  CAST(NULL AS FLOAT64) AS q25_med_count,
  CAST(NULL AS FLOAT64) AS q50_med_count,
  CAST(NULL AS FLOAT64) AS q75_med_count,
  ROUND(AVG(los_days),3) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 3) AS median_los_days,
  ROUND(SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)), 3) AS mortality_rate
FROM patient_metrics_with_rank
GROUP BY serotonergic_exposure

UNION ALL

SELECT
  'top_quartile' AS group_label,
  'complexity_q4' AS group_subgroup,
  COUNT(*) AS n_patients,
  ROUND(AVG(med_count),2) AS mean_med_count,
  ROUND(AVG(complexity_percentile),3) AS avg_complexity_percentile,
  CAST(NULL AS FLOAT64) AS q25_med_count,
  CAST(NULL AS FLOAT64) AS q50_med_count,
  CAST(NULL AS FLOAT64) AS q75_med_count,
  ROUND(AVG(los_days),3) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 3) AS median_los_days,
  ROUND(SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)), 3) AS mortality_rate
FROM patient_metrics_with_rank
WHERE complexity_quartile = 4

ORDER BY group_label, group_subgroup;