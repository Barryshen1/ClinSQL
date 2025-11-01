WITH cabg_procs AS (
  -- procedures that look like CABG based on the description
  SELECT
    p.subject_id,
    p.hadm_id,
    p.chartdate,
    p.icd_code,
    p.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    -- match descriptions that indicate coronary artery bypass procedures (case-insensitive)
    LOWER(d.long_title) LIKE '%coronary%'
    AND LOWER(d.long_title) LIKE '%bypass%'
    AND p.chartdate IS NOT NULL
),

first_cabg_per_subject AS (
  -- pick the first CABG procedure (earliest chartdate) per subject
  SELECT
    subject_id,
    hadm_id,
    chartdate
  FROM (
    SELECT
      subject_id,
      hadm_id,
      chartdate,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY chartdate, hadm_id) AS rn
    FROM cabg_procs
  )
  WHERE rn = 1
),

icu_los_per_hadm AS (
  -- total ICU LOS (days) summed across all ICU stays for the hadm
  SELECT
    hadm_id,
    SUM(los) AS total_icu_los_days
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY
    hadm_id
)

SELECT
  ROUND(AVG(fh.total_icu_los_days), 3) AS mean_icu_los_days,
  COUNT(*) AS n_patients
FROM
  first_cabg_per_subject fc
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
ON
  fc.subject_id = pat.subject_id
JOIN
  icu_los_per_hadm fh
ON
  fc.hadm_id = fh.hadm_id
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 74 AND 84;