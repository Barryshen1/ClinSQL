WITH first_icustays AS (
  -- First ICU stay per hospital admission (hadm_id)
  SELECT s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime, s.los
  FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) AS s
  WHERE s.rn = 1
),
dka_match AS (
  -- Admissions with a diagnosis of diabetic ketoacidosis
  SELECT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%diabetic ketoacidosis%'
),
dka_admissions AS (
  -- Admissions that are male, age 39-49 (based on anchor_age/year) and have DKA on the admission
  SELECT
    adm.subject_id,
    adm.hadm_id,
    fic.stay_id,
    fic.intime,
    fic.los AS icu_los_days,
    (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_adm,
    UPPER(p.gender) AS gender,
    CASE WHEN adm.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN first_icustays fic ON adm.hadm_id = fic.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON adm.subject_id = p.subject_id
  JOIN dka_match ON adm.subject_id = dka_match.subject_id AND adm.hadm_id = dka_match.hadm_id
  WHERE UPPER(p.gender) = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 39 AND 49
),
per_admission AS (
  -- Compute per-admission diagnostic intensity: distinct procedures in first 24h of first ICU stay
  SELECT
    da.subject_id,
    da.hadm_id,
    da.stay_id,
    da.intime,
    da.icu_los_days,
    da.age_at_adm,
    da.gender,
    da.mortality_flag,
    COALESCE((
      SELECT COUNT(DISTINCT pe.itemid)
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      WHERE pe.stay_id = da.stay_id
        AND pe.starttime >= da.intime
        AND pe.starttime < TIMESTAMP_ADD(da.intime, INTERVAL 24 HOUR)
    ), 0) AS proc_count
  FROM dka_admissions da
)
SELECT
  quintile,
  COUNT(*) AS stays,
  AVG(proc_count) AS mean_proc_count,
  MIN(proc_count) AS min_proc_count,
  MAX(proc_count) AS max_proc_count,
  AVG(icu_los_days) AS mean_icu_los_days,
  100.0 * SUM(mortality_flag) / COUNT(*) AS hospital_mortality_percent
FROM (
  SELECT
     pa.*,
     NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM per_admission pa
) AS t
GROUP BY quintile
ORDER BY quintile;