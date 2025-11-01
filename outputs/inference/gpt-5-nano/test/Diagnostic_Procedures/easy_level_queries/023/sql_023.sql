WITH female_82_92_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'Female'
    AND CASE
          WHEN p.anchor_age IS NULL OR p.anchor_year IS NULL THEN NULL
          ELSE p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
        END BETWEEN 82 AND 92
)

, cardiac_counts AS (
  SELECT pcd.hadm_id,
         COUNT(DISTINCT pcd.icd_code) AS cardiac_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pcd
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
    ON pcd.icd_code = dp.icd_code
   AND pcd.icd_version = dp.icd_version
  WHERE pcd.hadm_id IN (SELECT hadm_id FROM female_82_92_admissions)
    AND (
      LOWER(dp.long_title) LIKE '%cardiac%'
      OR LOWER(dp.long_title) LIKE '%coronary%'
      OR LOWER(dp.long_title) LIKE '%angioplasty%'
      OR LOWER(dp.long_title) LIKE '%bypass%'
      OR LOWER(dp.long_title) LIKE '%pacemaker%'
      OR LOWER(dp.long_title) LIKE '%valve%'
      OR LOWER(dp.long_title) LIKE '%ablation%'
    )
  GROUP BY pcd.hadm_id
)

, all_hosp_card_counts AS (
  SELECT f.hadm_id,
         COALESCE(cc.cardiac_proc_count, 0) AS cardiac_proc_count
  FROM female_82_92_admissions f
  LEFT JOIN cardiac_counts cc
    ON f.hadm_id = cc.hadm_id
)

SELECT
  PERCENTILE_CONT(cardiac_proc_count, 0.25) OVER () AS p25_cardic_procedures
FROM all_hosp_card_counts
LIMIT 1;