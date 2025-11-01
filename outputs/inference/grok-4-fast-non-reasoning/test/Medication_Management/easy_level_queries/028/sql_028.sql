WITH dapt_patients AS (
  -- Identify admissions with concurrent DAPT (aspirin + clopidogrel overlap)
  SELECT DISTINCT p.subject_id, pr1.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr1
    ON a.subject_id = pr1.subject_id AND a.hadm_id = pr1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr2
    ON a.subject_id = pr2.subject_id AND a.hadm_id = pr2.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND pr1.drug LIKE '%ASPIRIN%'
    AND pr2.drug LIKE '%CLOPIDOGREL%'
    AND pr1.starttime <= pr2.stoptime
    AND pr2.starttime <= pr1.stoptime
    AND pr1.starttime IS NOT NULL
    AND pr1.stoptime IS NOT NULL
    AND pr2.starttime IS NOT NULL
    AND pr2.stoptime IS NOT NULL
),

antiplatelet_prescriptions AS (
  -- All antiplatelet prescriptions for DAPT patients
  SELECT DISTINCT dp.subject_id, dp.hadm_id, pr.pharmacy_id,
         pr.drug, pr.starttime, pr.stoptime,
         TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM dapt_patients dp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON dp.subject_id = pr.subject_id AND dp.hadm_id = pr.hadm_id
  WHERE (pr.drug LIKE '%ASPIRIN%'
         OR pr.drug LIKE '%CLOPIDOGREL%'
         OR pr.drug LIKE '%PRASUGREL%'
         OR pr.drug LIKE '%TICAGRELOR%'
         OR pr.drug LIKE '%TICLOPIDINE%')
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),

single_antiplatelet AS (
  -- Filter to single (non-DAPT) antiplatelet: no overlap with both aspirin + clopidogrel in same admission
  SELECT ap.*
  FROM antiplatelet_prescriptions ap
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE drug LIKE '%ASPIRIN%' OR drug LIKE '%CLOPIDOGREL%'
  ) combo ON ap.subject_id = combo.subject_id AND ap.hadm_id = combo.hadm_id
  GROUP BY ap.subject_id, ap.hadm_id, ap.pharmacy_id, ap.drug, ap.starttime, ap.stoptime, ap.duration_days
  HAVING COUNTIF(combo.hadm_id IS NOT NULL) < 2  -- Less than full DAPT overlap per admission
     OR ap.duration_days IS NULL  -- Exclude if duration invalid
)

-- Compute SD of (average) single antiplatelet durations per patient
SELECT STDDEV(duration_avg) AS sd_single_antiplatelet_duration_days
FROM (
  SELECT subject_id, AVG(duration_days) AS duration_avg
  FROM single_antiplatelet
  GROUP BY subject_id
  HAVING COUNT(duration_days) > 0  -- Patients with at least one valid single prescription
);