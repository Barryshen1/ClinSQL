WITH pneumonia_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 76 AND 86 AND dicd.long_title LIKE '%Pneumonia%'
),
med_complexity AS (
  SELECT pa.hadm_id, COUNT(DISTINCT p.drug) AS unique_drugs
  FROM pneumonia_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON pa.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN pa.admittime AND (pa.admittime + INTERVAL 7 DAY)
  GROUP BY pa.hadm_id
),
admission_stats AS (
  SELECT 
    mc.hadm_id,
    mc.unique_drugs,
    NTILE(3) OVER (ORDER BY mc.unique_drugs) AS tertile,
    DATETIME_DIFF(pa.dischtime, pa.admittime, HOUR) / 24.0 AS los,
    pa.hospital_expire_flag,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = pa.subject_id AND a2.hadm_id != pa.hadm_id
        AND a2.admittime BETWEEN pa.dischtime AND DATETIME_ADD(pa.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30d
  FROM med_complexity mc
  INNER JOIN pneumonia_admissions pa ON mc.hadm_id = pa.hadm_id
)
SELECT 
  tertile,
  COUNT(hadm_id) AS count_admissions,
  MIN(unique_drugs) AS min_unique_drugs,
  AVG(unique_drugs) AS avg_unique_drugs,
  MAX(unique_drugs) AS max_unique_drugs,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(CAST(readmitted_30d AS INT64)) * 100 AS readmission_30d_pct
FROM admission_stats
GROUP BY tertile
ORDER BY tertile;