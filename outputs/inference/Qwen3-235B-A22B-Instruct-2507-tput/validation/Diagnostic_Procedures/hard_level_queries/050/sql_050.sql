WITH patient_ami_stays AS (
  SELECT DISTINCT
    pat.subject_id,
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients pat
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON pat.subject_id = icu.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
    ON icu.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year)) BETWEEN 76 AND 86
    AND d_diag.icd_code LIKE 'I21%'
    AND diag.icd_version = 10
),
procedures_24h AS (
  SELECT
    p.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_proc_count
  FROM patient_ami_stays p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON p.stay_id = pe.stay_id
    AND pe.starttime >= p.intime
    AND pe.starttime <= p.intime + INTERVAL '24' HOUR
  GROUP BY p.stay_id
),
quartiles AS (
  SELECT
    stay_id,
    distinct_proc_count,
    NTILE(4) OVER (ORDER BY distinct_proc_count) AS quartile
  FROM procedures_24h
)
SELECT
  q.quartile,
  AVG(q.distinct_proc_count) AS mean_procedure_count,
  AVG(p.icu_los) AS mean_icu_los,
  100.0 * AVG(CAST(p.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_percent
FROM quartiles q
INNER JOIN patient_ami_stays p ON q.stay_id = p.stay_id
GROUP BY q.quartile
ORDER BY q.quartile;