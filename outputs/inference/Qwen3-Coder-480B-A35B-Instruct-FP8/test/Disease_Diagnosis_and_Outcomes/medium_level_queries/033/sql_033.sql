WITH postop_admissions AS (
  -- Identify admissions with postoperative complications
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    -- Postoperative complication ICD codes
    (
      (d.icd_version = 9 AND d.icd_code BETWEEN 'E8940' AND 'E8949')
      OR
      (d.icd_version = 10 AND (
        (d.icd_code BETWEEN 'Y830' AND 'Y838') OR
        (d.icd_code BETWEEN 'Y840' AND 'Y848')
      ))
    )
),

eligible_patients AS (
  -- Filter patients by age and gender
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    a.los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    postop_admissions a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
),

comorbidity_counts AS (
  -- Count comorbidities (diagnoses with seq_num > 1)
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd
  WHERE
    seq_num > 1
  GROUP BY
    hadm_id
),

admission_features AS (
  SELECT
    ep.*,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count,
    CASE
      WHEN i.hadm_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status,
    CASE
      WHEN ep.los_days <= 5 THEN '≤5'
      ELSE '>5'
    END AS los_category,
    CASE
      WHEN COALESCE(cc.comorbidity_count, 0) BETWEEN 0 AND 1 THEN '0–1'
      WHEN COALESCE(cc.comorbidity_count, 0) = 2 THEN '2'
      ELSE '≥3'
    END AS comorbidity_bin
  FROM
    eligible_patients ep
  LEFT JOIN
    comorbidity_counts cc
    ON ep.hadm_id = cc.hadm_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON ep.hadm_id = i.hadm_id
)

SELECT
  icu_status,
  los_category,
  comorbidity_bin,
  COUNT(*) AS N,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent,
  ROUND(AVG(comorbidity_count), 2) AS avg_comorbidity_count
FROM
  admission_features
GROUP BY
  icu_status,
  los_category,
  comorbidity_bin
ORDER BY
  icu_status,
  los_category,
  comorbidity_bin;