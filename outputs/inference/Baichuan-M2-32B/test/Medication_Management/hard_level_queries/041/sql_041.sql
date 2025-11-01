WITH
  eligible_admissions AS (
    SELECT
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
    FROM
      `physionet-data.mimiciv_3_1_hosp`.admissions a
    JOIN
      `physionet-data.mimiciv_3_1_hosp`.patients p
      ON a.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 40 AND 50
  ),
  hf_admissions AS (
    SELECT
      ea.*
    FROM
      eligible_admissions ea
    JOIN
      `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
      ON ea.hadm_id = di.hadm_id
    JOIN
      `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE
      d.icd_code IN ('I10', 'I11', 'I13', 'I25.1', 'I50')
      AND d.icd_version = 10
  ),
  med_complexity AS (
    SELECT
      hf.hadm_id,
      COUNT(DISTINCT p.drug) AS med_complexity
    FROM
      hf_admissions hf
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp`.prescriptions p
      ON hf.hadm_id = p.hadm_id
      AND p.starttime BETWEEN hf.admittime AND TIMESTAMP_ADD(hf.admittime, INTERVAL 7 DAY)
    GROUP BY
      hf.hadm_id
  ),
  admission_metrics AS (
    SELECT
      hf.hadm_id,
      hf.subject_id,
      hf.admittime,
      hf.dischtime,
      hf.hospital_expire_flag,
      TIMESTAMP_DIFF(hf.dischtime, hf.admittime, DAY) AS los,
      (SELECT COUNT(*)
       FROM `physionet-data.mimiciv_3_1_hosp`.admissions a2
       WHERE a2.subject_id = hf.subject_id
         AND a2.hadm_id != hf.hadm_id
         AND a2.admittime > hf.dischtime
         AND a2.admittime <= TIMESTAMP_ADD(hf.dischtime, INTERVAL 30 DAY)
      ) > 0 AS readmission_30d
    FROM
      hf_admissions hf
  ),
  combined AS (
    SELECT
      mc.hadm_id,
      mc.med_complexity,
      am.los,
      am.hospital_expire_flag,
      am.readmission_30d
    FROM
      med_complexity mc
    JOIN
      admission_metrics am
      ON mc.hadm_id = am.hadm_id
  ),
  quintiles AS (
    SELECT
      *,
      NTILE(5) OVER (ORDER BY med_complexity) AS quintile
    FROM
      combined
  )
SELECT
  quintile,
  COUNT(*) AS patient_count,
  CONCAT(MIN(med_complexity), '-', MAX(med_complexity)) AS score_range,
  AVG(los) AS mean_los,
  AVG(CAST(hospital_expire_flag AS INT64)) AS in_hospital_mortality,
  AVG(CAST(readmission_30d AS INT64)) AS readmission_30d
FROM
  quintiles
GROUP BY
  quintile
ORDER BY
  quintile;