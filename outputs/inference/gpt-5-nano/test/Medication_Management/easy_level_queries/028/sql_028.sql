WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) = 'female'
    AND p.anchor_age BETWEEN 44 AND 54
),
antiplatelet_prescriptions AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    LOWER(pr.drug) AS drug,
    pr.starttime,
    pr.stoptime
  FROM cohort_admissions AS ca
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = ca.subject_id
   AND pr.hadm_id = ca.hadm_id
  WHERE (
        LOWER(pr.drug) LIKE '%aspirin%'
        OR LOWER(pr.drug) LIKE '%acetylsalicylic%'
        OR LOWER(pr.drug) LIKE '%asa%'
        OR LOWER(pr.drug) LIKE '%clopidogrel%'
        OR LOWER(pr.drug) LIKE '%prasugrel%'
        OR LOWER(pr.drug) LIKE '%ticagrelor%'
      )
  -- ensure the prescription occurs during the admission
  AND pr.starttime >= ca.admittime
  AND pr.stoptime <= ca.dischtime
),
dapt_admissions AS (
  -- admissions where there exists at least two overlapping antiplatelet prescriptions with different drugs
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM cohort_admissions AS a
  JOIN antiplatelet_prescriptions AS ap1
    ON ap1.subject_id = a.subject_id AND ap1.hadm_id = a.hadm_id
  JOIN antiplatelet_prescriptions AS ap2
    ON ap2.subject_id = a.subject_id AND ap2.hadm_id = a.hadm_id
  WHERE ap1.drug != ap2.drug
    AND ap1.starttime < ap2.stoptime
    AND ap2.starttime < ap1.stoptime
)
SELECT
  STDDEV_SAMP(hours) AS sd_duration_hours
FROM (
  SELECT
    TIMESTAMP_DIFF(ap.stoptime, ap.starttime, SECOND) / 3600.0 AS hours
  FROM antiplatelet_prescriptions AS ap
  JOIN dapt_admissions AS d
    ON ap.subject_id = d.subject_id AND ap.hadm_id = d.hadm_id
);