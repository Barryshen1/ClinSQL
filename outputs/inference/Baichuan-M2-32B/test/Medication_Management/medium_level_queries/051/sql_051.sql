WITH base_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.admittime, TIMESTAMP(CONCAT(p.anchor_year - p.anchor_age, '-01-01')), DAY) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND TIMESTAMP_DIFF(a.admittime, TIMESTAMP(CONCAT(p.anchor_year - p.anchor_age, '-01-01')), DAY) BETWEEN 86 AND 96
),
diagnoses AS (
  SELECT
    d.hadm_id,
    CASE
      WHEN di.long_title LIKE '%diabetes%' THEN 'DM'
      WHEN di.long_title LIKE '%heart failure%' THEN 'HF'
    END AS condition
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
),
admissions_with_conditions AS (
  SELECT
    ba.*
  FROM
    base_admissions ba
  INNER JOIN (
    SELECT
      hadm_id
    FROM
      diagnoses
    WHERE
      condition IS NOT NULL
    GROUP BY
      hadm_id
    HAVING
      COUNT(DISTINCT condition) = 2  -- Both DM and HF
  ) c
  ON ba.hadm_id = c.hadm_id
),
medications AS (
  SELECT
    p.hadm_id,
    p.drug,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE ANY OF ('%metformin%', '%glipizide%', '%glyburide%', '%glimepiride%', '%pioglitazone%', '%rosiglitazone%', '%saxagliptin%', '%sitagliptin%', '%linagliptin%', '%alogliptin%', '%dapagliflozin%', '%empagliflozin%', '%canagliflozin%', '%sulfonylurea%', '%thiazolidinedione%', '%dpp-4%', '%sodium-glucose%', '%glucagon-like peptide-1%') THEN 'Oral Agents'
      ELSE NULL
    END AS class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE
    p.drug IS NOT NULL
),
medication_periods AS (
  SELECT
    m.hadm_id,
    m.class,
    m.drug,
    p.starttime,
    p.endtime
  FROM
    medications m
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` p
    ON m.hadm_id = p.hadm_id AND m.drug = p.medication
),
admission_periods AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    CASE
      WHEN TIMESTAMP_DIFF(dischtime, admittime, HOUR) >= 72 THEN dischtime - INTERVAL 72 HOUR
      ELSE admittime
    END AS late_start
  FROM
    admissions_with_conditions
),
early_late_flags AS (
  SELECT
    ap.hadm_id,
    mp.class,
    -- Early: first 12h
    MAX(CASE WHEN mp.starttime BETWEEN ap.admittime AND ap.admittime + INTERVAL 12 HOUR THEN 1 ELSE 0 END) AS early_present,
    -- Late: last 72h (or entire admission if shorter)
    MAX(CASE WHEN mp.starttime BETWEEN ap.late_start AND ap.dischtime THEN 1 ELSE 0 END) AS late_present
  FROM
    admission_periods ap
  LEFT JOIN
    medication_periods mp
    ON ap.hadm_id = mp.hadm_id
  GROUP BY
    ap.hadm_id, mp.class
),
aggregated AS (
  SELECT
    class,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    SUM(early_present) AS early_count,
    SUM(late_present) AS late_count,
    -- Transitions: among early users, how many continued (late_present=1) or stopped (late_present=0)
    SUM(CASE WHEN early_present = 1 AND late_present = 1 THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN early_present = 1 AND late_present = 0 THEN 1 ELSE 0 END) AS stopped_count
  FROM
    early_late_flags
  GROUP BY
    class
)
SELECT
  class,
  -- Rates as percentages
  ROUND(100.0 * early_count / total_admissions, 2) AS early_rate,
  ROUND(100.0 * late_count / total_admissions, 2) AS late_rate,
  -- Transitions: only for patients with early medication
  ROUND(100.0 * continued_count / NULLIF(SUM(CASE WHEN early_present = 1 THEN 1 ELSE 0 END), 0), 2) AS continued_percent,
  ROUND(100.0 * stopped_count / NULLIF(SUM(CASE WHEN early_present = 1 THEN 1 ELSE 0 END), 0), 2) AS stopped_percent
FROM
  aggregated
GROUP BY
  class
ORDER BY
  class;