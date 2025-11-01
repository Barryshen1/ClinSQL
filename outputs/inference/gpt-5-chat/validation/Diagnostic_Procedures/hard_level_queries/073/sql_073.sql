WITH first_icu AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id
   AND i.hadm_id = a.hadm_id
  WHERE i.stay_id = (
      SELECT MIN(stay_id)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i2
      WHERE i2.subject_id = i.subject_id
    )
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
hepatic_failure AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%hepatic failure%'
),
proc_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT pr.icd_code) AS proc_count,
    f.los,
    f.hospital_expire_flag
  FROM first_icu f
  JOIN hepatic_failure h
    ON f.subject_id = h.subject_id
   AND f.hadm_id = h.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON f.subject_id = pr.subject_id
   AND f.hadm_id = pr.hadm_id
   AND pr.chartdate >= DATE(f.intime)
   AND pr.chartdate <= DATE_ADD(DATE(f.intime), INTERVAL 3 DAY)
  GROUP BY f.subject_id, f.hadm_id, f.stay_id, f.los, f.hospital_expire_flag
),
proc_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    proc_count,
    los,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY proc_count) AS proc_quartile
  FROM proc_counts
)
SELECT
  proc_quartile,
  COUNT(DISTINCT subject_id) AS n_patients,
  MIN(proc_count) AS min_procedures,
  MAX(proc_count) AS max_procedures,
  ROUND(AVG(proc_count),2) AS avg_procedures,
  ROUND(AVG(los),2) AS mean_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)
        / COUNT(*), 2) AS hosp_mortality_pct
FROM proc_quartiles
GROUP BY proc_quartile
ORDER BY proc_quartile;