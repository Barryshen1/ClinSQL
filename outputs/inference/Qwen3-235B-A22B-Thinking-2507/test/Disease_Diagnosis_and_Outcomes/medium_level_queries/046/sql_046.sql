WITH heart_failure_patients AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE 
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 72 AND 82
    AND a.dischtime IS NOT NULL
),
comorbidity_counts AS (
  SELECT 
    hadm_id,
    COUNTIF(seq_num > 1) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
categorized AS (
  SELECT 
    hfp.*,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count,
    CASE 
      WHEN hfp.hospital_los <= 3 THEN '≤3'
      WHEN hfp.hospital_los BETWEEN 4 AND 6 THEN '4-6'
      WHEN hfp.hospital_los BETWEEN 7 AND 10 THEN '7-10'
      WHEN hfp.hospital_los > 10 THEN '>10'
    END AS los_category
  FROM heart_failure_patients hfp
  LEFT JOIN comorbidity_counts cc
    ON hfp.hadm_id = cc.hadm_id
)
SELECT
  CASE WHEN icu_status = 1 THEN 'ICU' ELSE 'non-ICU' END AS icu_group,
  los_category,
  AVG(hospital_expire_flag) AS mortality_rate,
  APPROX_QUANTILES(hospital_los, 100)[OFFSET(50)] AS median_los,
  AVG(comorbidity_count) AS avg_comorbidity_count,
  COUNT(*) AS patient_count
FROM categorized
GROUP BY icu_group, los_category
ORDER BY 
  CASE icu_group WHEN 'ICU' THEN 1 ELSE 2 END,
  CASE los_category
    WHEN '≤3' THEN 1
    WHEN '4-6' THEN 2
    WHEN '7-10' THEN 3
    WHEN '>10' THEN 4
  END;