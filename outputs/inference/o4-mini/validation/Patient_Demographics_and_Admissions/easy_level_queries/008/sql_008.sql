WITH pci_events AS (
  -- Identify all PCI procedures
  SELECT
    p.subject_id,
    p.hadm_id,
    p.chartdate
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON p.icd_code = d.icd_code
     AND p.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%percutaneous coronary intervention%'
),
first_pci AS (
  -- Get each patient's first PCI
  SELECT
    subject_id,
    ARRAY_AGG(STRUCT(hadm_id, chartdate) ORDER BY chartdate LIMIT 1)[OFFSET(0)] AS first_event
  FROM
    pci_events
  GROUP BY
    subject_id
),
index_admissions AS (
  -- Restrict to men aged 52–62 at the time of their first PCI admission
  SELECT
    fp.subject_id,
    fp.first_event.hadm_id       AS index_hadm_id,
    fp.first_event.chartdate     AS pci_date,
    a.admittime,
    a.dischtime,
    p.anchor_age
  FROM
    first_pci fp
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON fp.subject_id = a.subject_id
     AND fp.first_event.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON fp.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
readmission_flags AS (
  -- For each index admission, check for a 30-day readmission
  SELECT
    ia.subject_id,
    ia.index_hadm_id,
    ia.dischtime,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE
          a2.subject_id = ia.subject_id
          AND a2.admittime > ia.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted_within_30d
  FROM
    index_admissions ia
)
-- Compute the overall 30-day readmission rate
SELECT
  ROUND(
    100.0 * SUM(readmitted_within_30d) / COUNT(1),
    2
  ) AS pct_readmission_30d
FROM
  readmission_flags;