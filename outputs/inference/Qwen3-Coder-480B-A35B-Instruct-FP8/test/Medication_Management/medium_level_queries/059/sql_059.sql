WITH cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND icu.los >= 1
    AND DATETIME_DIFF(icu.outtime, icu.intime, HOUR) >= 24
),

diabetes_hf AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE
    (d.icd_code LIKE 'E11%' OR d.icd_code LIKE '250.00')
    OR
    (d.icd_code LIKE 'I50%' OR d.icd_code LIKE '428%')
  GROUP BY
    hadm_id
  HAVING
    COUNT(DISTINCT CASE WHEN d.icd_code LIKE 'E11%' OR d.icd_code LIKE '250.00' THEN 1 END) > 0
    AND
    COUNT(DISTINCT CASE WHEN d.icd_code LIKE 'I50%' OR d.icd_code LIKE '428%' THEN 1 END) > 0
),

eligible_stays AS (
  SELECT c.*
  FROM cohort c
  JOIN diabetes_hf dh ON c.hadm_id = dh.hadm_id
),

meds_classified AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    LOWER(p.drug) AS drug,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'insulin|metformin|glipizide|glyburide|sitagliptin|liraglutide') THEN 'Antidiabetic'
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'metoprolol|carvedilol|bisoprolol|propranolol') THEN 'Beta-blocker'
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'lisinopril|enalapril|losartan|telmisartan|sacubitril|valsartan') THEN 'ACEi/ARB/ARNI'
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'furosemide|bumetanide|torsemide') THEN 'Loop diuretic'
    END AS med_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    eligible_stays es ON p.hadm_id = es.hadm_id
  WHERE
    p.starttime >= es.intime
    AND p.starttime <= es.outtime
),

med_window_flags AS (
  SELECT
    mc.subject_id,
    es.stay_id,
    mc.med_class,
    CASE
      WHEN mc.starttime BETWEEN es.intime AND DATETIME_ADD(es.intime, INTERVAL 48 HOUR) THEN 1
      ELSE 0
    END AS in_first_48h,
    CASE
      WHEN mc.starttime BETWEEN DATETIME_SUB(es.outtime, INTERVAL 24 HOUR) AND es.outtime THEN 1
      ELSE 0
    END AS in_final_24h
  FROM
    meds_classified mc
  JOIN
    eligible_stays es ON mc.hadm_id = es.hadm_id
  WHERE
    mc.med_class IS NOT NULL
),

patient_med_flags AS (
  SELECT
    stay_id,
    med_class,
    MAX(in_first_48h) AS started_first_48h,
    MAX(in_final_24h) AS started_final_24h
  FROM
    med_window_flags
  GROUP BY
    stay_id,
    med_class
),

summary_stats AS (
  SELECT
    med_class,
    COUNT(*) AS total_patients,
    SUM(started_first_48h) AS started_48h,
    SUM(started_final_24h) AS started_24h,
    ROUND(SUM(started_first_48h) * 100.0 / COUNT(*), 2) AS pct_48h,
    ROUND(SUM(started_final_24h) * 100.0 / COUNT(*), 2) AS pct_24h,
    ROUND((SUM(started_final_24h) - SUM(started_first_48h)) * 100.0 / COUNT(*), 2) AS diff_pp
  FROM
    patient_med_flags
  GROUP BY
    med_class
)

SELECT
  med_class,
  pct_48h,
  pct_24h,
  diff_pp
FROM
  summary_stats
ORDER BY
  med_class;