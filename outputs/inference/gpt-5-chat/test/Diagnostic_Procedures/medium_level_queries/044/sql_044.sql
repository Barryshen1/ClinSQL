WITH lower_gi_bleed_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND UPPER(ddi.long_title) LIKE '%LOWER%GI%BLEED%'
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
),
diagnostic_counts AS (
  SELECT
    lg.subject_id,
    lg.hadm_id,
    lg.los_days,
    CASE 
      WHEN lg.los_days BETWEEN 1 AND 3 THEN 'LOS_1_3'
      WHEN lg.los_days BETWEEN 4 AND 7 THEN 'LOS_4_7'
    END AS los_bucket,
    COUNT(DISTINCT pr.seq_num) AS num_diagnostics,
    CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'NoICU' END AS icu_status
  FROM lower_gi_bleed_admissions lg
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON lg.subject_id = pr.subject_id AND lg.hadm_id = pr.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
      AND (
        UPPER(dp.long_title) LIKE '%IMAGING%'
        OR UPPER(dp.long_title) LIKE '%X-RAY%'
        OR UPPER(dp.long_title) LIKE '%CT%'
        OR UPPER(dp.long_title) LIKE '%MRI%'
        OR UPPER(dp.long_title) LIKE '%ULTRASOUND%'
        OR UPPER(dp.long_title) LIKE '%ECG%'
        OR UPPER(dp.long_title) LIKE '%EEG%'
        OR UPPER(dp.long_title) LIKE '%PULMONARY FUNCTION%'
      )
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON lg.subject_id = icu.subject_id AND lg.hadm_id = icu.hadm_id
  GROUP BY lg.subject_id, lg.hadm_id, lg.los_days, los_bucket, icu_status
)
SELECT
  los_bucket,
  icu_status,
  AVG(num_diagnostics) AS mean_num_diagnostics
FROM diagnostic_counts
GROUP BY los_bucket, icu_status
ORDER BY los_bucket, icu_status;