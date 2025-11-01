WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.intime   AS icu_outtime_in,
    icu.outtime  AS icu_outtime,
    p.anchor_age,
    p.gender,
    adm.admittime,
    adm.deathtime       AS inhospital_death_time,
    p.dod               AS death_time
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.hadm_id = adm.hadm_id
    -- Filter gender and age
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    -- Ensure there is at least one ICH diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE
        d.hadm_id = icu.hadm_id
        AND dd.long_title LIKE '%Intracranial hemorrhage%'
    )
),

flags AS (
  SELECT
    c.*,
    -- Death within 30 days of ICU outtime?
    IF(
      c.death_time IS NOT NULL
      AND DATE_DIFF(DATE(c.death_time), DATE(c.icu_outtime), DAY) <= 30,
      1, 0
    ) AS death_within_30d,
    -- AKI flag: any N17.x diagnosis
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = c.hadm_id
          AND d.icd_code LIKE 'N17%'
      ), 1, 0
    ) AS aki_flag,
    -- ARDS flag: any J80 diagnosis
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = c.hadm_id
          AND d.icd_code = 'J80'
      ), 1, 0
    ) AS ards_flag
  FROM cohort c
),

scored AS (
  SELECT
    *,
    -- Simple composite risk score = sum of AKI + ARDS
    (aki_flag + ards_flag) AS risk_score,
    -- Survival days from ICU outtime to death
    CASE
      WHEN death_time IS NOT NULL THEN DATE_DIFF(DATE(death_time), DATE(icu_outtime), DAY)
      ELSE NULL
    END AS survival_days
  FROM flags
),

stats AS (
  SELECT
    COUNT(*) AS cohort_size,
    -- 30-day mortality rate
    AVG(death_within_30d) AS mortality_30d_rate,
    -- AKI and ARDS rates
    AVG(aki_flag)   AS aki_rate,
    AVG(ards_flag)  AS ards_rate,
    -- Composite risk score percentiles: returns array [min, p25, p50, p75, max]
    APPROX_QUANTILES(risk_score, 4) AS risk_score_quartiles
  FROM scored
),

median_survival AS (
  SELECT
    -- median survival among decedents
    APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days
  FROM scored
  WHERE survival_days IS NOT NULL
)

SELECT
  s.cohort_size,
  s.mortality_30d_rate,
  s.aki_rate,
  s.ards_rate,
  -- Unpack quartiles: [0th,min, p25, p50, p75, max]
  s.risk_score_quartiles[OFFSET(1)] AS risk_score_p25,
  s.risk_score_quartiles[OFFSET(2)] AS risk_score_p50,
  s.risk_score_quartiles[OFFSET(3)] AS risk_score_p75,
  m.median_survival_days
FROM stats s
CROSS JOIN median_survival m;