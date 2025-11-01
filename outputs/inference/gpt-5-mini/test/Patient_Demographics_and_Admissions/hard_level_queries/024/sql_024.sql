WITH index_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    -- fractional LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, MINUTE), 1440.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    dx.hadm_id = adm.hadm_id
    AND dx.seq_num = 1  -- principal diagnosis
  WHERE
    -- demographics & payer
    UPPER(p.gender) = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(COALESCE(adm.insurance, '')) LIKE '%medicare%'
    -- admitted from ED (robust to variations)
    AND LOWER(COALESCE(adm.admission_location, '')) LIKE '%emergency%'
    -- principal ischemic stroke: ICD-10 I63* or ICD-9 433*/434*
    AND (
      (SAFE_CAST(dx.icd_version AS INT64) = 10 AND dx.icd_code LIKE 'I63%')
      OR (SAFE_CAST(dx.icd_version AS INT64) = 9 AND (dx.icd_code LIKE '433%' OR dx.icd_code LIKE '434%'))
    )
    -- ensure valid times
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),

index_with_readmit AS (
  SELECT
    ia.*,
    -- readmitted within 30 days (any subsequent admission for same subject within 30 days after discharge)
    EXISTS(
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime IS NOT NULL
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS readmitted
  FROM index_admissions ia
)

SELECT
  COUNT(*) AS total_index_admissions,
  SUM(CASE WHEN readmitted THEN 1 ELSE 0 END) AS n_readmitted_30d,
  100.0 * SAFE_DIVIDE(SUM(CASE WHEN readmitted THEN 1 ELSE 0 END), COUNT(*)) AS readmission_rate_pct_30d,
  -- median LOS (approx) for readmitted group (days)
  (SELECT
     IFNULL(quantiles[OFFSET(1)], NULL)
   FROM (
     SELECT APPROX_QUANTILES(los_days, 2) AS quantiles
     FROM index_with_readmit
     WHERE readmitted
   )
  ) AS median_los_readmitted_days,
  -- median LOS (approx) for non-readmitted group (days)
  (SELECT
     IFNULL(quantiles[OFFSET(1)], NULL)
   FROM (
     SELECT APPROX_QUANTILES(los_days, 2) AS quantiles
     FROM index_with_readmit
     WHERE NOT readmitted
   )
  ) AS median_los_nonreadmitted_days,
  -- percent of index stays with LOS > 5 days
  100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days > 5 THEN 1 ELSE 0 END), COUNT(*)) AS pct_index_los_gt_5
FROM index_with_readmit;