WITH ami_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      d_icd.long_title LIKE '%acute myocardial infarction%'
      OR d_icd.long_title LIKE '%AMI%'
      OR d.icd_code LIKE 'I21%'
      OR d.icd_code LIKE 'I22%'
      OR (d.icd_version = 9 AND d.icd_code LIKE '410%')
    )
),

med_complexity AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_complexity_score
  FROM ami_patients a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.hadm_id = pr.hadm_id
    AND pr.starttime >= a.admittime
    AND pr.starttime <= a.admittime + INTERVAL '24' HOUR
  GROUP BY a.hadm_id
),

readmission_flag AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS thirty_day_readmission
  FROM ami_patients a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
),

combined AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COALESCE(m.med_complexity_score, 0) AS med_complexity_score,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    r.thirty_day_readmission,
    NTILE(3) OVER (ORDER BY COALESCE(m.med_complexity_score, 0)) AS tertile
  FROM ami_patients a
  LEFT JOIN med_complexity m ON a.hadm_id = m.hadm_id
  LEFT JOIN readmission_flag r ON a.hadm_id = r.hadm_id
)

SELECT
  tertile,
  COUNT(*) AS admission_count,
  MIN(med_complexity_score) AS score_min,
  MAX(med_complexity_score) AS score_max,
  AVG(med_complexity_score) AS score_mean,
  AVG(los_days) AS los_mean,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS inhospital_mortality_pct,
  AVG(CAST(thirty_day_readmission AS FLOAT64)) * 100 AS thirty_day_readmission_pct
FROM combined
GROUP BY tertile
ORDER BY tertile;