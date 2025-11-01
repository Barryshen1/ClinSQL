WITH PatientHF AS (
  -- Identify patients with heart failure (HF) diagnosis
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 48
    AND d.icd_code LIKE 'I50%' -- ICD-10 codes for heart failure
),
PatientAgeGroup AS (
  -- Identify patients within the age range 43-53
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),
ComorbidityBurden AS (
  -- Calculate comorbidity burden (simplified approach using Charlson Comorbidity Index - CCI)
  -- This is a simplified example; a full CCI calculation is more complex
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('I50%', 'I10%', 'I11%', 'I12%', 'I13%', 'I25%', 'I48%', 'I51%', 'I70%', 'I71%', 'I72%', 'I73%', 'I74%', 'I75%', 'I79%', 'J40%', 'J41%', 'J42%', 'J43%', 'J44%', 'J45%', 'J46%', 'J80%', 'J81%', 'J82%', 'J83%', 'J84%', 'J85%', 'J86%', 'J90%', 'J91%', 'J92%', 'J93%', 'J94%', 'J95%', 'J96%', 'J98%', 'K70%', 'K71%', 'K72%', 'K73%', 'K74%', 'K75%', 'K76%', 'K77%', 'K78%', 'K79%', 'K80%', 'K81%', 'K82%', 'K83%', 'K85%', 'K86%', 'K87%', 'K88%', 'K89%', 'K90%', 'K91%', 'K92%', 'K93%', 'K94%', 'K95%', 'K96%', 'N18%', 'N19%', 'N20%', 'N21%', 'N22%', 'N23%', 'N24%', 'N25%', 'N26%', 'N27%', 'N28%', 'N29%', 'N30%', 'N31%', 'N32;