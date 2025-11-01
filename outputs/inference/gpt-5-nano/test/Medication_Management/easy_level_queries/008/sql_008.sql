WITH male_admissions AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),

-- Aspirin prescriptions during the admission
aspirin AS (
  SELECT m.subject_id, m.hadm_id, pr.starttime AS asp_start, pr.stoptime AS asp_stop
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN male_admissions m
    ON pr.subject_id = m.subject_id
   AND pr.hadm_id = m.hadm_id
  WHERE LOWER(pr.drug) LIKE '%aspirin%'
),

-- P2Y12 inhibitor prescriptions during the admission
p2y12 AS (
  SELECT m.subject_id, m.hadm_id, pr.starttime AS p2_start, pr.stoptime AS p2_stop
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN male_admissions m
    ON pr.subject_id = m.subject_id
   AND pr.hadm_id = m.hadm_id
  WHERE LOWER(pr.drug) IN ('clopidogrel','prasugrel','ticlopidine','ticagrelor')
),

-- Overlaps between aspirin intervals and P2Y12 intervals within the same admission
overlaps AS (
  SELECT a.hadm_id,
         TIMESTAMP(GREATEST(a.asp_start, p2.p2_start)) AS ov_start,
         TIMESTAMP(LEAST(a.asp_stop, p2.p2_stop)) AS ov_end
  FROM aspirin a
  JOIN p2y12 p2
    ON a.subject_id = p2.subject_id
   AND a.hadm_id = p2.hadm_id
   -- ensure intervals actually overlap
   AND a.asp_start < p2.p2_stop
   AND p2.p2_start < a.asp_stop
),

-- We keep all overlapping segments; later we sum per admission
segments AS (
  SELECT hadm_id, ov_start, ov_end
  FROM overlaps
),

durations AS (
  -- Sum overlap duration per admission (in days)
  SELECT hadm_id,
         SUM(TIMESTAMP_DIFF(ov_end, ov_start, SECOND) / 86400.0) AS overlap_days_total
  FROM segments
  GROUP BY hadm_id
)

SELECT
  -- Use approximate quantiles to obtain the median across admissions with positive duration
  APPROX_QUANTILES(overlap_days_total, 2)[OFFSET(1)] AS median_inpatient_antiplatelet_duration_days
FROM durations
WHERE overlap_days_total > 0;