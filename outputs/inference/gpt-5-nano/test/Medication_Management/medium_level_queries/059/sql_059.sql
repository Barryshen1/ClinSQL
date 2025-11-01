with cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- approximate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    -- age window
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 60 AND 70
    -- require T2DM diagnosis on admission
    AND a.hadm_id IN (
      SELECT DISTINCT di.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%type 2 diabetes%'
         OR LOWER(dd.long_title) LIKE '%diabetes mellitus type 2%'
    )
    -- require HF diagnosis
    AND a.hadm_id IN (
      SELECT DISTINCT di.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%heart failure%'
         OR LOWER(dd.long_title) LIKE '%congestive heart failure%'
    )
    -- require discharge time (to enable final 24h window)
    AND a.dischtime IS NOT NULL
)

, first_window AS (
  SELECT
    c.hadm_id,
    -- Antidiabetics
    MAX(CASE
          WHEN pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
               AND REGEXP_CONTAINS(LOWER(pr.drug),
                    '(metformin|insulin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone)')
          THEN 1 ELSE 0
        END) AS first_diab_init,
    -- Beta-blockers
    MAX(CASE
          WHEN pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
               AND REGEXP_CONTAINS(LOWER(pr.drug),
                    '(metoprolol|carvedilol|bisoprolol|propranolol|atenolol|nebivolol|labetalol|nadolol)')
          THEN 1 ELSE 0
        END) AS first_bb_init,
    -- ACEi/ARB/ARNI
    MAX(CASE
          WHEN pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
               AND REGEXP_CONTAINS(LOWER(pr.drug),
                    '(lisinopril|enalapril|ramipril|benazepril|fosinopril|captopril|losartan|valsartan|olmesartan|sacubitril)')
          THEN 1 ELSE 0
        END) AS first_acearb_init,
    -- Loop diuretics
    MAX(CASE
          WHEN pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
               AND REGEXP_CONTAINS(LOWER(pr.drug),
                    '(furosemide|torsemide|bumetanide)')
          THEN 1 ELSE 0
        END) AS first_loop_init
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
)

, final_window AS (
  SELECT
    c.hadm_id,
    -- Antidiabetics
    MAX(CASE
          WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
               AND REGEXP_CONTAINS(LOWER(pr.drug),
                    '(metformin|insulin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone)')
          THEN 1 ELSE 0
        END) AS final_diab_init,
    -- Beta-blockers
    MAX(CASE
          WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
               AND REGEXP_CONTAINS(LOWER(pr.drug),
                    '(metoprolol|carvedilol|bisoprolol|propranolol|atenolol|nebivolol|labetalol|nadolol)')
          THEN 1 ELSE 0
        END) AS final_bb_init,
    -- ACEi/ARB/ARNI
    MAX(CASE
          WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
               AND REGEXP_CONTAINS(LOWER(pr.drug),
                    '(lisinopril|enalapril|ramipril|benazepril|fosinopril|captopril|losartan|valsartan|olmesartan|sacubitril)')
          THEN 1 ELSE 0
        END) AS final_acearb_init,
    -- Loop diuretics
    MAX(CASE
          WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
               AND REGEXP_CONTAINS(LOWER(pr.drug),
                    '(furosemide|torsemide|bumetanide)')
          THEN 1 ELSE 0
        END) AS final_loop_init
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
)

SELECT
  'Antidiabetics' AS class_name,
  100.0 * AVG(IFNULL(fd.first_diab_init, 0)) AS first_48h_initiation_pct,
  100.0 * AVG(IFNULL(ff.final_diab_init, 0)) AS final_24h_initiation_pct,
  100.0 * ABS(AVG(IFNULL(fd.first_diab_init, 0)) - AVG(IFNULL(ff.final_diab_init, 0))) AS diff_pp
FROM cohort c
JOIN first_window fd ON fd.hadm_id = c.hadm_id
JOIN final_window ff ON ff.hadm_id = c.hadm_id

UNION ALL
SELECT
  'Beta-blockers' AS class_name,
  100.0 * AVG(IFNULL(fd.first_bb_init, 0)) AS first_48h_initiation_pct,
  100.0 * AVG(IFNULL(ff.final_bb_init, 0)) AS final_24h_initiation_pct,
  100.0 * ABS(AVG(IFNULL(fd.first_bb_init, 0)) - AVG(IFNULL(ff.final_bb_init, 0))) AS diff_pp
FROM cohort c
JOIN first_window fd ON fd.hadm_id = c.hadm_id
JOIN final_window ff ON ff.hadm_id = c.hadm_id

UNION ALL
SELECT
  'ACEi/ARB/ARNI' AS class_name,
  100.0 * AVG(IFNULL(fd.first_acearb_init, 0)) AS first_48h_initiation_pct,
  100.0 * AVG(IFNULL(ff.final_acearb_init, 0)) AS final_24h_initiation_pct,
  100.0 * ABS(AVG(IFNULL(fd.first_acearb_init, 0)) - AVG(IFNULL(ff.final_acearb_init, 0))) AS diff_pp
FROM cohort c
JOIN first_window fd ON fd.hadm_id = c.hadm_id
JOIN final_window ff ON ff.hadm_id = c.hadm_id

UNION ALL
SELECT
  'Loop diuretics' AS class_name,
  100.0 * AVG(IFNULL(fd.first_loop_init, 0)) AS first_48h_initiation_pct,
  100.0 * AVG(IFNULL(ff.final_loop_init, 0)) AS final_24h_initiation_pct,
  100.0 * ABS(AVG(IFNULL(fd.first_loop_init, 0)) - AVG(IFNULL(ff.final_loop_init, 0))) AS diff_pp
FROM cohort c
JOIN first_window fd ON fd.hadm_id = c.hadm_id
JOIN final_window ff ON ff.hadm_id = c.hadm_id;