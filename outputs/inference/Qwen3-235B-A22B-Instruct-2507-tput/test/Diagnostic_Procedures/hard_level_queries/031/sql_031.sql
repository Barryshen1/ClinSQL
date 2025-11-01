WITH patient_icu_hhs AS (
  SELECT DISTINCT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 66 AND 76
    AND d_diag.icd_code = 'E11.01'  -- HHS proxy
),
procedure_counts AS (
  SELECT 
    pih.stay_id,
    pih.subject_id,
    pih.hadm_id,
    pih.admittime,
    pih.dischtime,
    pih.hospital_expire_flag,
    COUNT(pe.stay_id) AS procedure_count_48h
  FROM patient_icu_hhs pih
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pih.stay_id = pe.stay_id
    AND pe.starttime >= pih.intime
    AND pe.starttime <= pih.intime + INTERVAL '48' HOUR
  GROUP BY pih.stay_id, pih.subject_id, pih.hadm_id, pih.admittime, pih.dischtime, pih.hospital_expire_flag
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count_48h) AS quintile
  FROM procedure_counts
),
readmissions AS (
  SELECT 
    q.*,
    CASE 
      WHEN LAG(q.dischtime) OVER (PARTITION BY q.subject_id ORDER BY q.admittime) IS NULL THEN 0  -- first admission
      WHEN q.admittime <= LAG(q.dischtime) OVER (PARTITION BY q.subject_id ORDER BY q.admittime) + INTERVAL '30' DAY THEN 1
      ELSE 0
    END AS is_30day_readmission
  FROM quintiles q
),
final_stats AS (
  SELECT
    quintile,
    COUNT(stay_id) AS num_icu_stays,
    AVG(procedure_count_48h) AS mean_procedures,
    MIN(procedure_count_48h) AS min_procedures,
    MAX(procedure_count_48h) AS max_procedures,
    AVG(hospital_expire_flag) * 100 AS hospital_mortality_pct,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_hospital_los_days
  FROM readmissions
  GROUP BY quintile
),
readmission_rate AS (
  SELECT
    quintile,
    AVG(is_30day_readmission) * 100 AS readmission_30day_pct
  FROM readmissions
  GROUP BY quintile
)
SELECT
  fs.quintile,
  fs.num_icu_stays,
  fs.mean_procedures,
  fs.min_procedures,
  fs.max_procedures,
  fs.hospital_mortality_pct,
  fs.mean_hospital_los_days,
  COALESCE(rr.readmission_30day_pct, 0) AS readmission_30day_pct
FROM final_stats fs
LEFT JOIN readmission_rate rr
  ON fs.quintile = rr.quintile
ORDER BY fs.quintile;