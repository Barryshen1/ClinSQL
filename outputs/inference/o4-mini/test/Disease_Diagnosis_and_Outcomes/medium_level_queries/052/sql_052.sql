WITH stroke_adms AS (
  -- admissions of males age 52–62 with at least one stroke diagnosis
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND LOWER(dd.long_title) LIKE '%stroke%'
  GROUP BY
    p.subject_id, a.hadm_id, p.anchor_age, p.gender, a.admittime, a.dischtime, a.hospital_expire_flag
),
comorb_counts AS (
  -- count distinct non-stroke diagnoses per admission
  SELECT
    sa.*,
    COUNT(DISTINCT CASE
      WHEN LOWER(dd.long_title) NOT LIKE '%stroke%' THEN d.icd_code
      ELSE NULL END) AS comorb_count
  FROM
    stroke_adms sa
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  GROUP BY
    sa.subject_id, sa.hadm_id, sa.anchor_age, sa.gender, sa.admittime, sa.dischtime, sa.hospital_expire_flag
),
with_icu_los AS (
  -- add ICU flag and hospital LOS
  SELECT
    cc.*,
    CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag,
    CASE
      WHEN DATE_DIFF(DATE(cc.dischtime), DATE(cc.admittime), DAY) <= 5 THEN '≤5'
      ELSE '>5'
    END AS los_bin
  FROM
    comorb_counts cc
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      USING(subject_id, hadm_id)
),
with_tertiles AS (
  -- assign comorbidity tertiles
  SELECT
    *,
    NTILE(3) OVER (ORDER BY comorb_count) AS comorb_tert
  FROM
    with_icu_los
),
with_ckd_diab AS (
  -- add CKD and diabetes flags
  SELECT
    wt.*,
    MAX(IF(LOWER(dd.long_title) LIKE '%chronic kidney%', 1, 0)) AS ckd_flag,
    MAX(IF(LOWER(dd.long_title) LIKE '%diabetes%', 1, 0)) AS diabetes_flag
  FROM
    with_tertiles wt
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  GROUP BY
    wt.subject_id, wt.hadm_id, wt.anchor_age, wt.gender,
    wt.admittime, wt.dischtime, wt.hospital_expire_flag,
    wt.comorb_count, wt.icu_flag, wt.los_bin, wt.comorb_tert
)
-- final aggregation
SELECT
  icu_flag,
  los_bin,
  comorb_tert,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
  ROUND(100.0 * SUM(ckd_flag) / COUNT(*), 1) AS ckd_pct,
  ROUND(100.0 * SUM(diabetes_flag) / COUNT(*), 1) AS diabetes_pct
FROM
  with_ckd_diab
GROUP BY
  icu_flag,
  los_bin,
  comorb_tert
ORDER BY
  icu_flag,
  los_bin,
  comorb_tert;