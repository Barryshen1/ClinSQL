WITH dka_patients AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON diag.icd_code = ddi.icd_code
    AND diag.icd_version = ddi.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 39 AND 49
    AND LOWER(ddi.long_title) LIKE '%ketoacidosis%'
),
first_icu_stays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los
  FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
  WHERE rn = 1
),
procedures_24h AS (
  SELECT fi.subject_id,
         fi.hadm_id,
         fi.stay_id,
         COUNT(DISTINCT pe.itemid) AS procedure_count,
         MAX(fi.los) AS icu_los,
         MAX(adm.hospital_expire_flag) AS hospital_expire_flag
  FROM first_icu_stays fi
  JOIN dka_patients dka
    ON fi.subject_id = dka.subject_id
    AND fi.hadm_id = dka.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fi.subject_id = pe.subject_id
    AND fi.hadm_id = pe.hadm_id
    AND fi.stay_id = pe.stay_id
    AND pe.starttime >= fi.intime
    AND pe.starttime < DATETIME_ADD(fi.intime, INTERVAL 24 HOUR)
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON fi.hadm_id = adm.hadm_id
  GROUP BY fi.subject_id, fi.hadm_id, fi.stay_id
),
quintiles AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY procedure_count) AS proc_quintile
  FROM procedures_24h
)
SELECT proc_quintile,
       COUNT(*) AS num_stays,
       ROUND(AVG(procedure_count),2) AS mean_proc_count,
       MIN(procedure_count) AS min_proc_count,
       MAX(procedure_count) AS max_proc_count,
       ROUND(AVG(icu_los),2) AS mean_icu_los_days,
       ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)),2) AS hospital_mortality_percent
FROM quintiles
GROUP BY proc_quintile
ORDER BY proc_quintile;