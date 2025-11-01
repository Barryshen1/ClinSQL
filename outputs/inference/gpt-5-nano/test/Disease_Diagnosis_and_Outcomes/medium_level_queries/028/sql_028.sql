WITH HF_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),
HF_with_comorb AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.los_days,
    h.hospital_expire_flag,
    COUNT(DISTINCT di.icd_code) AS comorb_cnt
  FROM HF_admissions AS h
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = h.subject_id
   AND di.hadm_id = h.hadm_id
  GROUP BY
    h.subject_id, h.hadm_id, h.admittime, h.dischtime, h.los_days, h.hospital_expire_flag
),
Mortality AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.admittime,
    s.dischtime,
    s.los_days,
    s.hospital_expire_flag,
    s.comorb_cnt,
    CASE WHEN s.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hosp_mort
  FROM HF_with_comorb AS s
)

SELECT
  los_quartile,
  comorbidity_burden,
  COUNT(*) AS n_admissions,
  SUM(in_hosp_mort) AS in_hosp_mort,
  SAFE_DIVIDE(SUM(in_hosp_mort), COUNT(*)) * 100 AS in_hosp_mortality_percent
FROM (
  SELECT
    m.*,
    NTILE(4) OVER (ORDER BY m.los_days) AS los_quartile,
    CASE
      WHEN PERCENT_RANK() OVER (ORDER BY m.comorb_cnt) <= 1.0/3 THEN 'Low'
      WHEN PERCENT_RANK() OVER (ORDER BY m.comorb_cnt) <= 2.0/3 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_burden
  FROM Mortality AS m
)
GROUP BY los_quartile, comorbidity_burden
ORDER BY los_quartile, comorbidity_burden;