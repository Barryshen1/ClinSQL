WITH patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_icu_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 74 AND 84
),
first_icu_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN patient_age pa ON i.subject_id = pa.subject_id
),
admissions_with_gib AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%gastrointestinal bleed%'
    OR LOWER(d.long_title) LIKE '%hematemesis%'
    OR LOWER(d.long_title) LIKE '%melena%'
    OR LOWER(d.long_title) LIKE '%upper gi bleed%'
),
diagnostic_items AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(category) LIKE '%diagnostic%'
    OR LOWER(label) LIKE '%endoscop%'
    OR LOWER(label) LIKE '%echo%'
    OR LOWER(label) LIKE '%x-ray%'
    OR LOWER(label) LIKE '%ct%'
    OR LOWER(label) LIKE '%mri%'
    OR LOWER(label) LIKE '%ultrasound%'
    OR LOWER(label) LIKE '%diagnostic%'
    OR LOWER(label) LIKE '%imaging%'
),
lab_events_72h AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN first_icu_stay fis ON le.hadm_id = fis.hadm_id
  WHERE le.charttime >= fis.intime
    AND le.charttime <= fis.intime + INTERVAL '72' HOUR
    AND le.charttime IS NOT NULL
  GROUP BY le.hadm_id
),
micro_events_72h AS (
  SELECT
    me.hadm_id,
    COUNT(*) AS micro_count
  FROM `physionet-data.mimiciv_3_1_hosp`.microbiologyevents me
  INNER JOIN first_icu_stay fis ON me.hadm_id = fis.hadm_id
  WHERE me.charttime >= fis.intime
    AND me.charttime <= fis.intime + INTERVAL '72' HOUR
    AND me.charttime IS NOT NULL
  GROUP BY me.hadm_id
),
icu_diag_proc_72h AS (
  SELECT
    pe.hadm_id,
    COUNT(*) AS icu_diag_proc_count
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  INNER JOIN diagnostic_items di ON pe.itemid = di.itemid
  INNER JOIN first_icu_stay fis ON pe.stay_id = fis.stay_id
  WHERE pe.starttime >= fis.intime
    AND pe.starttime <= fis.intime + INTERVAL '72' HOUR
  GROUP BY pe.hadm_id
),
diagnostic_intensity AS (
  SELECT
    fis.subject_id,
    fis.hadm_id,
    fis.stay_id,
    COALESCE(le.lab_count, 0) +
    COALESCE(me.micro_count, 0) +
    COALESCE(idp.icu_diag_proc_count, 0) AS diagnostic_count_72h
  FROM first_icu_stay fis
  INNER JOIN admissions_with_gib ag ON fis.hadm_id = ag.hadm_id
  LEFT JOIN lab_events_72h le ON fis.hadm_id = le.hadm_id
  LEFT JOIN micro_events_72h me ON fis.hadm_id = me.hadm_id
  LEFT JOIN icu_diag_proc_72h idp ON fis.hadm_id = idp.hadm_id
  WHERE fis.rn = 1
),
quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    diagnostic_count_72h,
    NTILE(4) OVER (ORDER BY diagnostic_count_72h) AS diagnostic_quartile
  FROM diagnostic_intensity
),
procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd
  GROUP BY hadm_id
),
admission_outcomes AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions
)
SELECT
  q.diagnostic_quartile,
  AVG(COALESCE(pc.procedure_count, 0)) AS mean_procedure_count,
  AVG(ao.los_days) AS mean_los_days,
  AVG(ao.hospital_expire_flag) AS in_hospital_mortality_rate
FROM quartiles q
LEFT JOIN procedure_counts pc ON q.hadm_id = pc.hadm_id
LEFT JOIN admission_outcomes ao ON q.hadm_id = ao.hadm_id
GROUP BY q.diagnostic_quartile
ORDER BY q.diagnostic_quartile;