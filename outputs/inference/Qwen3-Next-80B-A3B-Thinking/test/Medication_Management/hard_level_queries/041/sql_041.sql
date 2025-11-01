WITH hf_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '428%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.dischtime IS NOT NULL
),
medication_scores AS (
  SELECT
    hf.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM hf_patients hf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON hf.hadm_id = pr.hadm_id
    AND pr.starttime >= hf.admittime
    AND pr.starttime <= hf.admittime + INTERVAL '7' DAY
  GROUP BY hf.hadm_id
),
readmission AS (
  SELECT
    a1.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a1.subject_id
        AND a2.admittime > a1.dischtime
        AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
    ) THEN 1 ELSE 0 END AS readmit_30d
  FROM hf_patients a1
),
combined AS (
  SELECT
    hf.hadm_id,
    ms.med_count,
    DATE_DIFF(hf.dischtime, hf.admittime, DAY) AS los_days,
    hf.hospital_expire_flag,
    r.readmit_30d
  FROM hf_patients hf
  LEFT JOIN medication_scores ms ON hf.hadm_id = ms.hadm_id
  LEFT JOIN readmission r ON hf.hadm_id = r.hadm_id
)
SELECT
  quintile,
  MIN(med_count) AS min_score,
  MAX(med_count) AS max_score,
  COUNT(*) AS patient_count,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality,
  AVG(readmit_30d) AS thirty_day_readmission
FROM (
  SELECT
    NTILE(5) OVER (ORDER BY med_count) AS quintile,
    med_count,
    los_days,
    hospital_expire_flag,
    readmit_30d
  FROM combined
) AS subquery
GROUP BY quintile
ORDER BY quintile;