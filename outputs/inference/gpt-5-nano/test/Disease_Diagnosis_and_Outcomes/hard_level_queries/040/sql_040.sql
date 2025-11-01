WITH ich_cohort AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    h.deathtime,
    -- age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM h.admittime) - p.anchor_year)) AS admit_age,
    -- comorbidity flags (0/1)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = h.hadm_id AND di.subject_id = h.subject_id
          AND (
            (di.icd_version = 9 AND (di.icd_code LIKE '250%')) OR
            (di.icd_version = 10 AND (di.icd_code LIKE 'E11%'))
          )
      ) THEN 1 ELSE 0
    END AS diabetes,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = h.hadm_id AND di.subject_id = h.subject_id
          AND (
            (di.icd_version = 9 AND (di.icd_code LIKE '428%' OR di.icd_code LIKE '404%' OR di.icd_code LIKE '429%')) OR
            (di.icd_version = 10 AND (di.icd_code LIKE 'I50%'))
          )
      ) THEN 1 ELSE 0
    END AS chf,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = h.hadm_id AND di.subject_id = h.subject_id
          AND (
            (di.icd_version = 9 AND (di.icd_code LIKE '584%')) OR
            (di.icd_version = 10 AND (di.icd_code LIKE 'N17%'))
          )
      ) THEN 1 ELSE 0
    END AS renal_failure,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = h.hadm_id AND di.subject_id = h.subject_id
          AND (
            (di.icd_version = 9 AND (di.icd_code LIKE '571%')) OR
            (di.icd_version = 10 AND (di.icd_code LIKE 'K70%'))
          )
      ) THEN 1 ELSE 0
    END AS liver_disease,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = h.hadm_id AND di.subject_id = h.subject_id
          AND (
            (di.icd_version = 9 AND (
              di.icd_code LIKE '14%' OR di.icd_code LIKE '15%' OR di.icd_code LIKE '16%' OR di.icd_code LIKE '17%' OR di.icd_code LIKE '18%' OR di.icd_code LIKE '19%'
            )) OR
            (di.icd_version = 10 AND (di.icd_code LIKE 'C%'))
          )
      ) THEN 1 ELSE 0
    END AS cancer,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = h.hadm_id AND di.subject_id = h.subject_id
          AND (
            (di.icd_version = 9 AND (
              di.icd_code LIKE '490%' OR di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code LIKE '493%' OR di.icd_code LIKE '494%' OR di.icd_code LIKE '495%' OR di.icd_code LIKE '496%'
            )) OR
            (di.icd_version = 10 AND (di.icd_code LIKE 'J44%'))
          )
      ) THEN 1 ELSE 0
    END AS copd
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` h
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON h.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM h.admittime) - p.anchor_year)) BETWEEN 69 AND 79
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_ich
      WHERE di_ich.hadm_id = h.hadm_id AND di_ich.subject_id = h.subject_id
        AND (
          (di_ich.icd_version = 9 AND (di_ich.icd_code LIKE '430%' OR di_ich.icd_code LIKE '431%' OR di_ich.icd_code LIKE '432%'))
          OR
          (di_ich.icd_version = 10 AND (di_ich.icd_code LIKE 'I60%' OR di_ich.icd_code LIKE 'I61%' OR di_ich.icd_code LIKE 'I62%'))
        )
    )
),

risk AS (
  SELECT
    ic.hadm_id,
    ic.subject_id,
    ic.admittime,
    ic.dischtime,
    ic.deathtime,
    ic.admit_age,
    ic.diabetes,
    ic.chf,
    ic.renal_failure,
    ic.liver_disease,
    ic.cancer,
    ic.copd,
    (CASE WHEN ic.admit_age < 70 THEN 0 WHEN ic.admit_age < 75 THEN 1 ELSE 2 END
     + ic.diabetes + ic.chf + ic.renal_failure + ic.liver_disease + ic.cancer + ic.copd) AS risk_score,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_mc
      WHERE di_mc.hadm_id = ic.hadm_id AND di_mc.subject_id = ic.subject_id AND (
        (di_mc.icd_version = 9 AND (di_mc.icd_code LIKE '480%' OR di_mc.icd_code LIKE '481%' OR di_mc.icd_code LIKE '482%' OR di_mc.icd_code LIKE '484%' OR di_mc.icd_code LIKE '485%' OR di_mc.icd_code LIKE '486%' OR di_mc.icd_code LIKE '038%'))
        OR
        (di_mc.icd_version = 10 AND (di_mc.icd_code LIKE 'J18%' OR di_mc.icd_code LIKE 'A41%' OR di_mc.icd_code LIKE 'N17%'))
      )
    ) THEN 1 ELSE 0 END AS major_comp
  FROM ich_cohort ic
),

expanded AS (
  SELECT
    risk.hadm_id,
    risk.subject_id,
    risk.admittime,
    risk.dischtime,
    risk.deathtime,
    risk.admit_age,
    risk.risk_score,
    risk.major_comp,
    (CASE WHEN risk.deathtime IS NOT NULL
           AND DATE(risk.deathtime) <= DATE(risk.admittime) + INTERVAL 30 DAY
          THEN 1 ELSE 0 END) AS mort30,
    (DATE(risk.dischtime) - DATE(risk.admittime)) AS los_days
  FROM risk
),

quad AS (
  SELECT
    risk.hadm_id,
    risk.subject_id,
    risk.admittime,
    risk.dischtime,
    risk.deathtime,
    risk.admit_age,
    risk.risk_score,
    risk.major_comp,
    (CASE WHEN risk.deathtime IS NOT NULL
           AND DATE(risk.deathtime) <= DATE(risk.admittime) + INTERVAL 30 DAY
          THEN 1 ELSE 0 END) AS mort30,
    (DATE(risk.dischtime) - DATE(risk.admittime)) AS los_days
  FROM risk
),
quad_with_quint AS (
  SELECT q.*,
         NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM quad q
),
median_per_quint AS (
  -- Median LOS among survivors (mort30 = 0), per quintile
  SELECT quintile,
         AVG(los_days) AS median_survivor_los
  FROM (
    SELECT quintile, los_days,
           ROW_NUMBER() OVER (PARTITION BY quintile ORDER BY los_days) AS rn,
           COUNT(*) OVER (PARTITION BY quintile) AS cnt
    FROM quad_with_quint
    WHERE mort30 = 0
  ) s
  WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
  GROUP BY quintile
),
final AS (
  SELECT
    wq.quintile,
    COUNT(*) AS n,
    100.0 * SUM(wq.mort30) / COUNT(*) AS mortality_30d_percent,
    100.0 * SUM(wq.major_comp) / COUNT(*) AS major_complication_percent,
    m.median_survivor_los
  FROM quad_with_quint wq
  LEFT JOIN median_per_quint m ON wq.quintile = m.quintile
  GROUP BY wq.quintile, m.median_survivor_los
)
SELECT *
FROM final
ORDER BY quintile;