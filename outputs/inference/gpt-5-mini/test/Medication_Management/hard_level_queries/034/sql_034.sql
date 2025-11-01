WITH cohort AS (
  -- female surgical admissions age 51-61 (anchor_age), require at least one procedure record
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      WHERE pr.hadm_id = a.hadm_id
    )
),
meds24 AS (
  -- distinct drugs started/administered in the first 24 hours from three hosp medication sources
  SELECT DISTINCT
    c.hadm_id,
    LOWER(TRIM(p.drug)) AS drug_norm
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
  WHERE p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND p.drug IS NOT NULL

  UNION DISTINCT

  SELECT DISTINCT
    c.hadm_id,
    LOWER(TRIM(ph.medication)) AS drug_norm
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.hadm_id = c.hadm_id
  WHERE ph.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND ph.medication IS NOT NULL

  UNION DISTINCT

  SELECT DISTINCT
    c.hadm_id,
    LOWER(TRIM(e.medication)) AS drug_norm
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON e.hadm_id = c.hadm_id
  WHERE e.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND e.medication IS NOT NULL
),
drug_flags AS (
  -- flag high-risk drugs by simple keyword regex; weight these more heavily
  SELECT
    hadm_id,
    drug_norm,
    CASE
      WHEN REGEXP_CONTAINS(drug_norm,
        r'(insulin|warfarin|heparin|dabigatran|rivaroxaban|apixaban|oxycodone|hydrocodone|morphine|fentanyl|methadone|propofol|clopidogrel|ticagrelor|vancomycin|gentamicin|amikacin|cisplatin|norepinephrine|epinephrine|noradrenaline|dopamine|rituximab|paclitaxel|cisplatin)') THEN 1
      ELSE 0
    END AS is_high_risk
  FROM meds24
),
complexity AS (
  -- compute weighted complexity per admission (2 points for each distinct high-risk drug, 1 for others)
  SELECT
    c.hadm_id,
    COALESCE(SUM(CASE WHEN df.is_high_risk = 1 THEN 2 ELSE 1 END), 0) AS complexity
  FROM cohort c
  LEFT JOIN drug_flags df
    ON df.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
),
admissions_with_flags AS (
  -- attach complexity and compute 30-day readmission flag
  SELECT
    c.*,
    COALESCE(comp.complexity, 0) AS complexity,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit30_flag
  FROM cohort c
  LEFT JOIN complexity comp
    ON comp.hadm_id = c.hadm_id
),
quartiled AS (
  -- assign quartiles by complexity and compute LOS in days
  SELECT
    awf.*,
    NTILE(4) OVER (ORDER BY complexity) AS complexity_quartile,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM admissions_with_flags awf
)

SELECT
  complexity_quartile,
  COUNT(*) AS admissions_count,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  CAST((APPROX_QUANTILES(los_days, 2))[OFFSET(1)] AS INT64) AS median_los_days,
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS in_hospital_mortality_pct,
  ROUND(100 * AVG(CAST(readmit30_flag AS FLOAT64)), 2) AS readmit30_pct
FROM quartiled
GROUP BY complexity_quartile
ORDER BY complexity_quartile;