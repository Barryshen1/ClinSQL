WITH pneu_dx AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN d.icd_code LIKE 'J69%' THEN 'aspiration'
      WHEN d.icd_code LIKE 'J18%' THEN 'community'
      ELSE NULL
    END AS pneu_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
    AND (d.icd_code LIKE 'J69%' OR d.icd_code LIKE 'J18%')
),
-- ensure one pneumonia type per admission
pneu_type AS (
  SELECT
    subject_id,
    hadm_id,
    pneu_type
  FROM (
    SELECT
      subject_id,
      hadm_id,
      pneu_type,
      COUNT(DISTINCT pneu_type) OVER (PARTITION BY subject_id, hadm_id) AS cnt_types
    FROM pneu_dx
  )
  WHERE cnt_types = 1
  GROUP BY subject_id, hadm_id, pneu_type
),
icu1 AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(intime) AS first_icu_in
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY subject_id, hadm_id
),
comorb AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) -
      SUM(CASE WHEN icd_code LIKE 'J69%' OR icd_code LIKE 'J18%' THEN 1 ELSE 0 END)
      AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
  GROUP BY hadm_id
),
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    pt.pneu_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_bin,
    CASE
      WHEN i.first_icu_in IS NOT NULL
       AND i.first_icu_in <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
      THEN 'Yes'
      ELSE 'No'
    END AS icu_day1,
    COALESCE(c.comorb_count,0) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN pneu_type pt
    ON a.subject_id = pt.subject_id
   AND a.hadm_id   = pt.hadm_id
  LEFT JOIN icu1 i
    ON a.subject_id = i.subject_id
   AND a.hadm_id   = i.hadm_id
  LEFT JOIN comorb c
    ON a.hadm_id = c.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),
agg AS (
  SELECT
    los_bin,
    icu_day1,
    pneu_type,
    COUNT(*) AS N,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_pct,
    AVG(comorb_count) AS avg_comorbidity
  FROM base
  GROUP BY los_bin, icu_day1, pneu_type
),
pivoted AS (
  SELECT
    los_bin,
    icu_day1,
    MAX(CASE WHEN pneu_type = 'aspiration' THEN N END)             AS N_asp,
    MAX(CASE WHEN pneu_type = 'community' THEN N END)             AS N_comm,
    MAX(CASE WHEN pneu_type = 'aspiration' THEN mortality_pct END) AS mort_asp,
    MAX(CASE WHEN pneu_type = 'community' THEN mortality_pct END) AS mort_comm,
    MAX(CASE WHEN pneu_type = 'aspiration' THEN avg_comorbidity END) AS comorb_asp,
    MAX(CASE WHEN pneu_type = 'community' THEN avg_comorbidity END) AS comorb_comm
  FROM agg
  GROUP BY los_bin, icu_day1
)
SELECT
  los_bin,
  icu_day1,
  N_asp,
  N_comm,
  mort_asp,
  mort_comm,
  SAFE_SUBTRACT(mort_asp, mort_comm)           AS abs_diff_pct,
  SAFE_DIVIDE(SAFE_SUBTRACT(mort_asp, mort_comm), mort_comm) * 100 AS rel_diff_pct,
  comorb_asp,
  comorb_comm
FROM pivoted
ORDER BY
  los_bin,
  icu_day1;