with diabetes and heart failure, report initiation rates (%) in first 48h versus last 12h for antidiabetics, beta‑blockers, ACEi/ARB/ARNI, loop diuretics, and net change.

WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diHF
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddHF
        ON diHF.icd_code = ddHF.icd_code AND diHF.icd_version = ddHF.icd_version
      WHERE diHF.subject_id = a.subject_id
        AND diHF.hadm_id = a.hadm_id
        AND (
          LOWER(ddHF.long_title) LIKE '%heart failure%'
          OR LOWER(ddHF.long_title) LIKE '%congestive heart failure%'
        )
    )
),
calc AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- First 48h initiations
    MAX(CASE
          WHEN p.starttime >= c.admittime
               AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
               AND (
                 LOWER(p.drug) LIKE '%insulin%' OR
                 LOWER(p.drug) LIKE '%metformin%' OR
                 LOWER(p.drug) LIKE '%glipizide%' OR
                 LOWER(p.drug) LIKE '%glyburide%' OR
                 LOWER(p.drug) LIKE '%glimepiride%' OR
                 LOWER(p.drug) LIKE '%pioglitazone%' OR
                 LOWER(p.drug) LIKE '%rosiglitazone%'
               )
          THEN 1 ELSE 0 END
    ) AS first48_antidiabetics,
    MAX(CASE
          WHEN p.starttime >= c.admittime
               AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
               AND (
                 LOWER(p.drug) LIKE '%metoprolol%' OR
                 LOWER(p.drug) LIKE '%atenolol%' OR
                 LOWER(p.drug) LIKE '%bisoprolol%' OR
                 LOWER(p.drug) LIKE '%carvedilol%' OR
                 LOWER(p.drug) LIKE '%propranolol%' OR
                 LOWER(p.drug) LIKE '%labetalol%'
               )
          THEN 1 ELSE 0 END
    ) AS first48_beta_blockers,
    MAX(CASE
          WHEN p.starttime >= c.admittime
               AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
               AND (
                 LOWER(p.drug) LIKE '%sacubitril%' OR
                 LOWER(p.drug) LIKE '%valsartan%' OR
                 LOWER(p.drug) LIKE '%losartan%' OR
                 LOWER(p.drug) LIKE '%olmesartan%' OR
                 LOWER(p.drug) LIKE '%telmisartan%' OR
                 LOWER(p.drug) LIKE '%irbesartan%' OR
                 LOWER(p.drug) LIKE '%candesartan%' OR
                 LOWER(p.drug) LIKE '%ramipril%' OR
                 LOWER(p.drug) LIKE '%lisinopril%' OR
                 LOWER(p.drug) LIKE '%enalapril%' OR
                 LOWER(p.drug) LIKE '%benazepril%' OR
                 LOWER(p.drug) LIKE '%quinapril%'
               )
          THEN 1 ELSE 0 END
    ) AS first48_ace_arb_arni,
    MAX(CASE
          WHEN p.starttime >= c.admittime
               AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
               AND (
                 LOWER(p.drug) LIKE '%furosemide%' OR
                 LOWER(p.drug) LIKE '%torsemide%' OR
                 LOWER(p.drug) LIKE '%bumetanide%'
               )
          THEN 1 ELSE 0 END
    ) AS first48_loop_diuretics,
    -- Last 12h initiations
    MAX(CASE
          WHEN p.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
               AND p.starttime <= c.dischtime
               AND (
                 LOWER(p.drug) LIKE '%insulin%' OR
                 LOWER(p.drug) LIKE '%metformin%' OR
                 LOWER(p.drug) LIKE '%glipizide%' OR
                 LOWER(p.drug) LIKE '%glyburide%' OR
                 LOWER(p.drug) LIKE '%glimepiride%' OR
                 LOWER(p.drug) LIKE '%pioglitazone%' OR
                 LOWER(p.drug) LIKE '%rosiglitazone%'
               )
          THEN 1 ELSE 0 END
    ) AS last12_antidiabetics,
    MAX(CASE
          WHEN p.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
               AND p.starttime <= c.dischtime
               AND (
                 LOWER(p.drug) LIKE '%metoprolol%' OR
                 LOWER(p.drug) LIKE '%atenolol%' OR
                 LOWER(p.drug) LIKE '%bisoprolol%' OR
                 LOWER(p.drug) LIKE '%carvedilol%' OR
                 LOWER(p.drug) LIKE '%propranolol%' OR
                 LOWER(p.drug) LIKE '%labetalol%'
               )
          THEN 1 ELSE 0 END
    ) AS last12_beta_blockers,
    MAX(CASE
          WHEN p.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
               AND p.starttime <= c.dischtime
               AND (
                 LOWER(p.drug) LIKE '%sacubitril%' OR
                 LOWER(p.drug) LIKE '%valsartan%' OR
                 LOWER(p.drug) LIKE '%losartan%' OR
                 LOWER(p.drug) LIKE '%olmesartan%' OR
                 LOWER(p.drug) LIKE '%telmisartan%' OR
                 LOWER(p.drug) LIKE '%irbesartan%' OR
                 LOWER(p.drug) LIKE '%candesartan%'
               )
          THEN 1 ELSE 0 END
    ) AS last12_ace_arb_arni,
    MAX(CASE
          WHEN p.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
               AND p.starttime <= c.dischtime
               AND (
                 LOWER(p.drug) LIKE '%furosemide%' OR
                 LOWER(p.drug) LIKE '%torsemide%' OR
                 LOWER(p.drug) LIKE '%bumetanide%'
               )
          THEN 1 ELSE 0 END
    ) AS last12_loop_diuretics
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
)

SELECT
  COUNT(*) AS total_admissions,
  SUM(first48_antidiabetics) * 1.0 / COUNT(*) * 100 AS first48_antidiabetics_rate,
  SUM(last12_antidiabetics) * 1.0 / COUNT(*) * 100 AS last12_antidiabetics_rate,
  (SUM(last12_antidiabetics) - SUM(first48_antidiabetics)) * 1.0 / COUNT(*) * 100 AS net_change_antidiabetics,
  SUM(first48_beta_blockers) * 1.0 / COUNT(*) * 100 AS first48_beta_blockers_rate,
  SUM(last12_beta_blockers) * 1.0 / COUNT(*) * 100 AS last12_beta_blockers_rate,
  (SUM(last12_beta_blockers) - SUM(first48_beta_blockers)) * 1.0 / COUNT(*) * 100 AS net_change_beta_blockers,
  SUM(first48_ace_arb_arni) * 1.0 / COUNT(*) * 100 AS first48_ace_arb_arni_rate,
  SUM(last12_ace_arb_arni) * 1.0 / COUNT(*) * 100 AS last12_ace_arb_arni_rate,
  (SUM(last12_ace_arb_arni) - SUM(first48_ace_arb_arni)) * 1.0 / COUNT(*) * 100 AS net_change_ace_arb_arni,
  SUM(first48_loop_diuretics) * 1.0 / COUNT(*) * 100 AS first48_loop_diuretics_rate,
  SUM(last12_loop_diuretics) * 1.0 / COUNT(*) * 100 AS last12_loop_diuretics_rate,
  (SUM(last12_loop_diuretics) - SUM(first48_loop_diuretics)) * 1.0 / COUNT(*) * 100 AS net_change_loop_diuretics
FROM calc;