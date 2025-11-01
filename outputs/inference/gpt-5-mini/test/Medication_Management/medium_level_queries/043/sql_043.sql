WITH cohort AS (
  -- Admissions for male patients age 77-87 with both diabetes and heart failure diagnoses
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    -- has diabetes diagnosis (ICD-9 250* OR ICD-10 E10*/E11*)
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%'))
        )
    )
    -- has heart failure diagnosis (ICD-9 428* OR ICD-10 I50*)
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = 9 AND d2.icd_code LIKE '428%')
          OR (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%')
        )
    )
),

meds_raw AS (
  -- prescriptions for cohort admissions, restricted to starttime within admission
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    p.drug
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.starttime BETWEEN c.admittime AND c.dischtime
),

meds_classified AS (
  -- map prescriptions to medication classes using substring matching on drug name
  SELECT
    hadm_id,
    admittime,
    dischtime,
    starttime,
    LOWER(drug) AS drug_lower,
    CASE
      WHEN (
        LOWER(drug) LIKE '%insulin%' OR LOWER(drug) LIKE '%metformin%'
        OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%'
        OR LOWER(drug) LIKE '%glimepiride%' OR LOWER(drug) LIKE '%sitagliptin%'
        OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%empagliflozin%'
        OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%saxagliptin%'
        OR LOWER(drug) LIKE '%alogliptin%' OR LOWER(drug) LIKE '%liraglutide%'
        OR LOWER(drug) LIKE '%dulaglutide%' OR LOWER(drug) LIKE '%semaglutide%'
      ) THEN 'antidiabetic'
      WHEN (
        LOWER(drug) LIKE '%metoprolol%' OR LOWER(drug) LIKE '%atenolol%'
        OR LOWER(drug) LIKE '%propranolol%' OR LOWER(drug) LIKE '%carvedilol%'
        OR LOWER(drug) LIKE '%bisoprolol%' OR LOWER(drug) LIKE '%nebivolol%'
        OR LOWER(drug) LIKE '%nadolol%'
      ) THEN 'beta_blocker'
      WHEN (
        LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%enalapril%'
        OR LOWER(drug) LIKE '%ramipril%' OR LOWER(drug) LIKE '%losartan%'
        OR LOWER(drug) LIKE '%valsartan%' OR LOWER(drug) LIKE '%candesartan%'
        OR LOWER(drug) LIKE '%irbesartan%' OR LOWER(drug) LIKE '%sacubitril%'
        OR LOWER(drug) LIKE '%entresto%'
      ) THEN 'ace_arb_arni'
      WHEN (
        LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%bumetanide%'
        OR LOWER(drug) LIKE '%torsemide%'
      ) THEN 'loop_diuretic'
      ELSE NULL
    END AS med_class
  FROM meds_raw
  -- only keep rows that map to a class
  WHERE LOWER(drug) IS NOT NULL
),

earliest AS (
  -- earliest in-admission prescription time per hadm_id and class
  SELECT
    hadm_id,
    med_class AS class,
    MIN(starttime) AS first_start
  FROM meds_classified
  WHERE med_class IS NOT NULL
  GROUP BY hadm_id, med_class
),

classes AS (
  SELECT 'antidiabetic' AS class UNION ALL
  SELECT 'beta_blocker' UNION ALL
  SELECT 'ace_arb_arni' UNION ALL
  SELECT 'loop_diuretic'
),

totals AS (
  SELECT COUNT(*) AS total_admissions FROM cohort
)

SELECT
  cl.class,
  t.total_admissions,
  -- count of admissions with earliest in-admission start within first 48 hours
  ( SELECT COUNT(DISTINCT e.hadm_id)
    FROM earliest e
    JOIN cohort c ON e.hadm_id = c.hadm_id
    WHERE e.class = cl.class
      AND e.first_start <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  ) AS first48_count,
  ROUND(100.0 * (SELECT COUNT(DISTINCT e.hadm_id)
    FROM earliest e
    JOIN cohort c ON e.hadm_id = c.hadm_id
    WHERE e.class = cl.class
      AND e.first_start <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  ) / t.total_admissions, 2) AS first48_pct,
  -- count of admissions with earliest in-admission start in last 12 hours before discharge
  ( SELECT COUNT(DISTINCT e.hadm_id)
    FROM earliest e
    JOIN cohort c ON e.hadm_id = c.hadm_id
    WHERE e.class = cl.class
      AND e.first_start >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
      AND e.first_start <= c.dischtime
  ) AS last12_count,
  ROUND(100.0 * (SELECT COUNT(DISTINCT e.hadm_id)
    FROM earliest e
    JOIN cohort c ON e.hadm_id = c.hadm_id
    WHERE e.class = cl.class
      AND e.first_start >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
      AND e.first_start <= c.dischtime
  ) / t.total_admissions, 2) AS last12_pct,
  -- net change = last12_pct - first48_pct (expressed in percentage points)
  ROUND(
    100.0 * (
      (SELECT COUNT(DISTINCT e.hadm_id)
       FROM earliest e
       JOIN cohort c ON e.hadm_id = c.hadm_id
       WHERE e.class = cl.class
         AND e.first_start >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
         AND e.first_start <= c.dischtime
      )
      -
      (SELECT COUNT(DISTINCT e.hadm_id)
       FROM earliest e
       JOIN cohort c ON e.hadm_id = c.hadm_id
       WHERE e.class = cl.class
         AND e.first_start <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
      )
    ) / t.total_admissions, 2
  ) AS net_change_pct
FROM classes cl
CROSS JOIN totals t
ORDER BY cl.class;