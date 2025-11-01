WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di1
    ON di1.subject_id = a.subject_id AND di1.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d1
    ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
    ON di2.subject_id = a.subject_id AND di2.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d2
    ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE LOWER(d1.long_title) LIKE '%diabetes%'
    AND LOWER(d2.long_title) LIKE '%heart failure%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
)

-- 1) Antidiabetic
SELECT
  'Antidiabetic' AS drug_class,
  COUNT(*) AS total_cohort,
  100.0 * SUM(IF(first24, 1, 0)) / COUNT(*) AS pct_first24,
  100.0 * SUM(IF(last24, 1, 0)) / COUNT(*) AS pct_last24,
  SUM(IF(first24 AND last24, 1, 0)) AS count_continued,
  SUM(IF(NOT first24 AND last24, 1, 0)) AS count_initiated_late,
  SUM(IF(first24 AND NOT last24, 1, 0)) AS count_discontinued
FROM (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime,
         (EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
           WHERE pr.subject_id = c.subject_id
             AND pr.hadm_id = c.hadm_id
             AND pr.starttime <= c.admittime + INTERVAL 1 DAY
             AND IFNULL(pr.stoptime, pr.starttime) >= c.admittime
             AND (
               LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%insulin%' OR
               LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR
               LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR
               LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR
               LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%'
             )
         )) AS first24,
         (EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
           WHERE pr.subject_id = c.subject_id
             AND pr.hadm_id = c.hadm_id
             AND pr.starttime <= c.dischtime
             AND IFNULL(pr.stoptime, pr.starttime) >= c.dischtime - INTERVAL 1 DAY
             AND (
               LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%insulin%' OR
               LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR
               LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR
               LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR
               LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%'
             )
         )) AS last24
  FROM cohort c
) sub

UNION ALL

-- 2) Beta-blocker
SELECT
  'Beta-blocker' AS drug_class,
  COUNT(*) AS total_cohort,
  100.0 * SUM(IF(first24, 1, 0)) / COUNT(*) AS pct_first24,
  100.0 * SUM(IF(last24, 1, 0)) / COUNT(*) AS pct_last24,
  SUM(IF(first24 AND last24, 1, 0)) AS count_continued,
  SUM(IF(NOT first24 AND last24, 1, 0)) AS count_initiated_late,
  SUM(IF(first24 AND NOT last24, 1, 0)) AS count_discontinued
FROM (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime,
         (EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
           WHERE pr.subject_id = c.subject_id
             AND pr.hadm_id = c.hadm_id
             AND pr.starttime <= c.admittime + INTERVAL 1 DAY
             AND IFNULL(pr.stoptime, pr.starttime) >= c.admittime
             AND (
               LOWER(pr.drug) LIKE '%metoprolol%' OR LOWER(pr.drug) LIKE '%carvedilol%' OR
               LOWER(pr.drug) LIKE '%propranolol%' OR LOWER(pr.drug) LIKE '%atenolol%' OR
               LOWER(pr.drug) LIKE '%bisoprolol%' OR LOWER(pr.drug) LIKE '%nadolol%' OR
               LOWER(pr.drug) LIKE '%labetalol%' OR LOWER(pr.drug) LIKE '%nebivolol%'
             )
         )) AS first24,
         (EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
           WHERE pr.subject_id = c.subject_id
             AND pr.hadm_id = c.hadm_id
             AND pr.starttime <= c.dischtime
             AND IFNULL(pr.stoptime, pr.starttime) >= c.dischtime - INTERVAL 1 DAY
             AND (
               LOWER(pr.drug) LIKE '%metoprolol%' OR LOWER(pr.drug) LIKE '%carvedilol%' OR
               LOWER(pr.drug) LIKE '%propranolol%' OR LOWER(pr.drug) LIKE '%atenolol%' OR
               LOWER(pr.drug) LIKE '%bisoprolol%' OR LOWER(pr.drug) LIKE '%nadolol%' OR
               LOWER(pr.drug) LIKE '%labetalol%' OR LOWER(pr.drug) LIKE '%nebivolol%'
             )
         )) AS last24
  FROM cohort c
) sub

UNION ALL

-- 3) ACEi/ARB/ARNI
SELECT
  'ACEi/ARB/ARNI' AS drug_class,
  COUNT(*) AS total_cohort,
  100.0 * SUM(IF(first24, 1, 0)) / COUNT(*) AS pct_first24,
  100.0 * SUM(IF(last24, 1, 0)) / COUNT(*) AS pct_last24,
  SUM(IF(first24 AND last24, 1, 0)) AS count_continued,
  SUM(IF(NOT first24 AND last24, 1, 0)) AS count_initiated_late,
  SUM(IF(first24 AND NOT last24, 1, 0)) AS count_discontinued
FROM (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime,
         (EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
           WHERE pr.subject_id = c.subject_id
             AND pr.hadm_id = c.hadm_id
             AND pr.starttime <= c.admittime + INTERVAL 1 DAY
             AND IFNULL(pr.stoptime, pr.starttime) >= c.admittime
             AND (
               LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%enalapril%' OR LOWER(pr.drug) LIKE '%ramipril%' OR
               LOWER(pr.drug) LIKE '%benazepril%' OR LOWER(pr.drug) LIKE '%captopril%' OR LOWER(pr.drug) LIKE '%fosinopril%' OR
               LOWER(pr.drug) LIKE '%perindopril%' OR LOWER(pr.drug) LIKE '%quinapril%' OR LOWER(pr.drug) LIKE '%trandolapril%' OR
               LOWER(pr.drug) LIKE '%losartan%' OR LOWER(pr.drug) LIKE '%valsartan%' OR LOWER(pr.drug) LIKE '%olmesartan%' OR
               LOWER(pr.drug) LIKE '%irbesartan%' OR LOWER(pr.drug) LIKE '%candesartan%' OR LOWER(pr.drug) LIKE '%telmisartan%' OR
               LOWER(pr.drug) LIKE '%eprosartan%' OR LOWER(pr.drug) LIKE '%sacubitril%'
             )
         )) AS first24,
         (EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
           WHERE pr.subject_id = c.subject_id
             AND pr.hadm_id = c.hadm_id
             AND pr.starttime <= c.dischtime
             AND IFNULL(pr.stoptime, pr.starttime) >= c.dischtime - INTERVAL 1 DAY
             AND (
               LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%enalapril%' OR LOWER(pr.drug) LIKE '%ramipril%' OR
               LOWER(pr.drug) LIKE '%benazepril%' OR LOWER(pr.drug) LIKE '%captopril%' OR LOWER(pr.drug) LIKE '%fosinopril%' OR
               LOWER(pr.drug) LIKE '%perindopril%' OR LOWER(pr.drug) LIKE '%quinapril%' OR LOWER(pr.drug) LIKE '%trandolapril%' OR
               LOWER(pr.drug) LIKE '%losartan%' OR LOWER(pr.drug) LIKE '%valsartan%' OR LOWER(pr.drug) LIKE '%olmesartan%' OR
               LOWER(pr.drug) LIKE '%irbesartan%' OR LOWER(pr.drug) LIKE '%candesartan%' OR LOWER(pr.drug) LIKE '%telmisartan%' OR
               LOWER(pr.drug) LIKE '%eprosartan%' OR LOWER(pr.drug) LIKE '%sacubitril%'
             )
         )) AS last24
  FROM cohort c
) sub

UNION ALL

-- 4) Loop diuretics
SELECT
  'Loop diuretic' AS drug_class,
  COUNT(*) AS total_cohort,
  100.0 * SUM(IF(first24, 1, 0)) / COUNT(*) AS pct_first24,
  100.0 * SUM(IF(last24, 1, 0)) / COUNT(*) AS pct_last24,
  SUM(IF(first24 AND last24, 1, 0)) AS count_continued,
  SUM(IF(NOT first24 AND last24, 1, 0)) AS count_initiated_late,
  SUM(IF(first24 AND NOT last24, 1, 0)) AS count_discontinued
FROM (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime,
         (EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
           WHERE pr.subject_id = c.subject_id
             AND pr.hadm_id = c.hadm_id
             AND pr.starttime <= c.admittime + INTERVAL 1 DAY
             AND IFNULL(pr.stoptime, pr.starttime) >= c.admittime
             AND (
               LOWER(pr.drug) LIKE '%furosemide%' OR LOWER(pr.drug) LIKE '%bumetanide%' OR LOWER(pr.drug) LIKE '%torsemide%'
             )
         )) AS first24,
         (EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
           WHERE pr.subject_id = c.subject_id
             AND pr.hadm_id = c.hadm_id
             AND pr.starttime <= c.dischtime
             AND IFNULL(pr.stoptime, pr.starttime) >= c.dischtime - INTERVAL 1 DAY
             AND (
               LOWER(pr.drug) LIKE '%furosemide%' OR LOWER(pr.drug) LIKE '%bumetanide%' OR LOWER(pr.drug) LIKE '%torsemide%'
             )
         )) AS last24
  FROM cohort c
) sub

ORDER BY drug_class;