WITH PatientACS AS (
  -- Identify patients with ACS (Acute Coronary Syndrome)
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND d.icd_code IN ('410', '411', '413', '414', '420', '427', '428') -- ACS ICD-10 codes
),
LabInstability AS (
  -- Calculate lab instability score for each patient admission
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT le.itemid) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON a.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientACS)
    AND li.category IN ('Electrolytes', 'Coagulation', 'Blood Gas', 'Renal Function', 'Liver Function') -- Critical lab categories
    AND le.valuenum IS NOT NULL
    AND (
      (li.category = 'Electrolytes' AND (le.valuenum < 3.5 OR le.valuenum > 5.0)) -- Sodium
      OR (li.category = 'Electrolytes' AND (le.valuenum < 3.5 OR le.valuenum > 5.5)) -- Potassium
      OR (li.category = 'Coagulation' AND (le.valuenum < 100 OR le.valuenum > 150)) -- Platelets
      OR (li.category = 'Blood Gas' AND (le.valuenum < 7.3 OR le.valuenum > 7.5)) -- pH
      OR (li.category = 'Renal Function' AND (le.valuenum < 10 OR le.valuenum > 150)) -- Creatinine
      OR (li.category = 'Liver Function' AND (le.valuenum < 10 OR le.valuenum > 100)) -- AST/ALT
    )
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR) -- Within 72 hours of admission
  GROUP BY
    a.subject_id,
    a.hadm_id
),
Quartiles AS (
  -- Assign patients to quartiles based on lab instability score
  SELECT
    li.subject_id,
    li.hadm_id,
    li.critical_lab_count,
    NTILE(4) OVER (ORDER BY li.critical_lab_count) AS quartile
  FROM LabInstability AS li
),
MortalityLOS AS (
  -- Calculate mortality and average LOS per quartile
  SELECT
    q.quartile,
    COUNT(CASE WHEN a.hospital_expire_flag = 1 THEN a.subject_id ELSE NULL END) * 100.0 / COUNT(a.subject_id) AS mortality_percentage,
    AVG(a.los) AS avg_los
  FROM Quartiles AS q
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
  GROUP BY
    q.quartile
)
SELECT
  *
FROM MortalityLOS
ORDER BY
  quartile;