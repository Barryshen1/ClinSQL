WITH index_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.subject_id = di.subject_id
     AND a.hadm_id    = di.hadm_id
     AND di.seq_num   = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code    = d.icd_code
     AND di.icd_version = d.icd_version
  WHERE
    p.gender             = 'M'
    AND p.anchor_age     BETWEEN 50 AND 60
    AND a.insurance      = 'Medicare'
    AND a.admission_type = 'EMERGENCY'
    -- principal diagnosis is lower GI bleeding
    AND (
      LOWER(d.long_title) LIKE '%lower gastrointestinal hemorrhage%'
      OR LOWER(d.long_title) LIKE '%lower gi bleed%'
    )
),

with_readmit AS (
  SELECT
    ia.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE
        a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= ia.dischtime + INTERVAL 30 DAY
    ) AS readmitted_30d
  FROM
    index_adm ia
)

SELECT
  -- 30-day readmission rate (percent)
  ROUND(
    100 * SUM(CASE WHEN readmitted_30d THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS readmission_rate_pct,

  -- Median LOS among readmitted
  APPROX_QUANTILES(
    IF(readmitted_30d, los, NULL),
    2
  )[OFFSET(1)] AS median_los_readmitted,

  -- Median LOS among not readmitted
  APPROX_QUANTILES(
    IF(NOT readmitted_30d, los, NULL),
    2
  )[OFFSET(1)] AS median_los_not_readmitted,

  -- Percent with LOS > 6 days among readmitted
  ROUND(
    100 * SUM(CASE WHEN readmitted_30d AND los > 6 THEN 1 ELSE 0 END)
      / SUM(CASE WHEN readmitted_30d THEN 1 ELSE 0 END),
    2
  ) AS pct_los_gt6_readmitted,

  -- Percent with LOS > 6 days among not readmitted
  ROUND(
    100 * SUM(CASE WHEN NOT readmitted_30d AND los > 6 THEN 1 ELSE 0 END)
      / SUM(CASE WHEN NOT readmitted_30d THEN 1 ELSE 0 END),
    2
  ) AS pct_los_gt6_not_readmitted

FROM
  with_readmit;