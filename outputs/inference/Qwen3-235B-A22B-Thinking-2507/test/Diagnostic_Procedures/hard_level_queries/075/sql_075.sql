WITH dka_admissions AS (
  SELECT DISTINCT
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND diag.icd_version = 10
    AND (
      diag.icd_code LIKE 'E081%' OR
      diag.icd_code LIKE 'E091%' OR
      diag.icd_code LIKE 'E101%' OR
      diag.icd_code LIKE 'E111%' OR
      diag.icd_code LIKE 'E131%'
    )
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 39 AND 49
),
first_icu AS (
  SELECT
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
  INNER JOIN dka_admissions dka
    ON icu.hadm_id = dka.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON icu.hadm_id = adm.hadm_id
),
procedure_counts AS (
  SELECT
    fi.stay_id,
    fi.los,
    fi.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM first_icu fi
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON fi.stay_id = pe.stay_id
    AND pe.starttime >= fi.intime
    AND pe.starttime < TIMESTAMP_ADD(fi.intime, INTERVAL 24 HOUR)
  WHERE fi.rn = 1
  GROUP BY fi.stay_id, fi.los, fi.hospital_expire_flag
),
with_quintile AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM procedure_counts
)
SELECT
  quintile,
  COUNT(*) AS num_stays,
  AVG(proc_count) AS mean_proc_count,
  MIN(proc_count) AS min_proc_count,
  MAX(proc_count) AS max_proc_count,
  AVG(los) AS mean_icu_los,
  AVG(hospital_expire_flag) * 100 AS mortality_pct
FROM with_quintile
GROUP BY quintile
ORDER BY quintile;