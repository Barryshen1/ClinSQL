WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),
aspirin_int AS (
  -- Earliest start / latest stop for aspirin per admission
  SELECT
    subject_id,
    hadm_id,
    MIN(starttime) AS aspirin_start,
    MAX(stoptime)  AS aspirin_end
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%aspirin%'
  GROUP BY
    subject_id, hadm_id
),
p2y12_int AS (
  -- Earliest start / latest stop for P2Y12 inhibitor per admission
  SELECT
    subject_id,
    hadm_id,
    MIN(starttime) AS p2y12_start,
    MAX(stoptime)  AS p2y12_end
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) IN ('clopidogrel','prasugrel','ticagrelor','ticlopidine')
  GROUP BY
    subject_id, hadm_id
),
dual_therapy AS (
  -- Join cohort to both drug intervals and compute overlap in days
  SELECT
    c.subject_id,
    c.hadm_id,
    -- Compute overlap interval
    GREATEST(
      TIMESTAMP_DIFF(
        LEAST(a.aspirin_end, p.p2y12_end),
        GREATEST(a.aspirin_start, p.p2y12_start),
        DAY
      ), 0
    ) AS overlap_days
  FROM
    cohort c
    JOIN aspirin_int a
      USING(subject_id, hadm_id)
    JOIN p2y12_int p
      USING(subject_id, hadm_id)
  WHERE
    -- Ensure there is a positive overlap
    a.aspirin_end   >= p.p2y12_start
    AND p.p2y12_end >= a.aspirin_start
)
-- Final: median overlap duration in days
SELECT
  APPROX_QUANTILES(overlap_days, 2)[OFFSET(1)] AS median_dual_antiplatelet_days
FROM
  dual_therapy;