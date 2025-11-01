WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    a.admittime,
    a.dischtime,
    p.dod,
    a.hospital_expire_flag,
    CASE
      WHEN p.dod IS NOT NULL AND DATETIME_DIFF(p.dod, i.intime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND did.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND did.icd_code LIKE 'I21%' OR did.icd_code LIKE 'I22%' OR did.icd_code LIKE 'I23%')
    )
),

aki_cases AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    MAX(l.valuenum) AS peak_creat
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    d.label IN ('CREATININE', 'Creatinine')
    AND l.charttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 7 DAY)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
),

ards_cases AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.label LIKE '%PaO2/FiO2%'
    AND SAFE_CAST(ce.value AS FLOAT64) < 300
),

survival_days AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    DATETIME_DIFF(dod, icu_intime, DAY) AS survival_days
  FROM
    cohort
  WHERE
    died_within_30_days = 1
)

SELECT
  COUNT(*) AS cohort_size,
  AVG(died_within_30_days) AS mortality_30d_rate,
  AVG(CASE WHEN aki.subject_id IS NOT NULL THEN 1 ELSE 0 END) AS aki_rate,
  AVG(CASE WHEN ards.subject_id IS NOT NULL THEN 1 ELSE 0 END) AS ards_rate,
  (
    SELECT
      APPROX_QUANTILES(s.survival_days, 2)[ORDINAL(1)]
    FROM
      survival_days s
  ) AS median_survival_days
FROM
  cohort c
LEFT JOIN
  aki_cases aki
  ON c.subject_id = aki.subject_id AND c.hadm_id = aki.hadm_id AND c.stay_id = aki.stay_id
LEFT JOIN
  ards_cases ards
  ON c.subject_id = ards.subject_id AND c.hadm_id = ards.hadm_id AND c.stay_id = ards.stay_id;