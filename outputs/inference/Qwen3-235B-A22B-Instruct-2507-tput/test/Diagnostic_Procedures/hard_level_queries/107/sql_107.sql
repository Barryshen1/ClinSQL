WITH pt_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    DATETIME(p.anchor_year, 1, 1, 0, 0, 0) AS anchor_year_dt
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'F'
),
icu_with_age AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    pa.anchor_age + (EXTRACT(YEAR FROM i.intime) - pa.anchor_year) AS age_at_icu_adm
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN pt_age pa ON i.subject_id = pa.subject_id
  WHERE (pa.anchor_age + (EXTRACT(YEAR FROM i.intime) - pa.anchor_year)) BETWEEN 65 AND 75
),
first_icu_stay AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM icu_with_age
),
pe_diagnosis AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%pulmonary embolism%'
),
cohort AS (
  SELECT
    f.*
  FROM first_icu_stay f
  INNER JOIN pe_diagnosis p ON f.hadm_id = p.hadm_id
  WHERE f.rn = 1
),
procedure_counts AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    c.intime,
    c.los,
    COUNT(pv.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pv
    ON c.stay_id = pv.stay_id
    AND pv.starttime >= c.intime
    AND pv.starttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.stay_id, c.subject_id, c.hadm_id, c.intime, c.los
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM procedure_counts
)
SELECT
  q.quartile,
  COUNT(*) AS N,
  ROUND(AVG(q.procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(q.los), 2) AS mean_icu_los_days,
  ROUND(100.0 * AVG(COALESCE(a.hospital_expire_flag, 0)), 2) AS hospital_mortality_pct
FROM quartiles q
LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON q.hadm_id = a.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;