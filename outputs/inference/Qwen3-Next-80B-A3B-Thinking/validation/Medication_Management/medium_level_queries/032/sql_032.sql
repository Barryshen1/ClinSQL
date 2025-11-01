WITH eligible_patients AS (
  SELECT 
    p.subject_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      WHERE d1.subject_id = p.subject_id
        AND d1.icd_version = 10
        AND d1.icd_code LIKE 'E1%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.subject_id = p.subject_id
        AND d2.icd_version = 10
        AND d2.icd_code LIKE 'I50%'
    )
),

first_24h_regimen AS (
  SELECT 
    ep.subject_id,
    CASE
      WHEN MAX(CASE WHEN pr.drug LIKE '%Glargine%' OR pr.drug LIKE '%Detemir%' OR pr.drug LIKE '%NPH%' THEN 1 ELSE 0 END) = 1
        AND MAX(CASE WHEN (pr.drug LIKE '%Lispro%' OR pr.drug LIKE '%Aspart%' OR pr.drug LIKE '%Glulisine%' OR (pr.drug LIKE '%Regular%' AND (ph.frequency != 'sliding scale' OR ph.frequency IS NULL))) THEN 1 ELSE 0 END) = 1
        THEN 'Basal-Bolus'
      WHEN MAX(CASE WHEN pr.drug LIKE '%Glargine%' OR pr.drug LIKE '%Detemir%' OR pr.drug LIKE '%NPH%' THEN 1 ELSE 0 END) = 1
        AND MAX(CASE WHEN (pr.drug LIKE '%Lispro%' OR pr.drug LIKE '%Aspart%' OR pr.drug LIKE '%Glulisine%' OR (pr.drug LIKE '%Regular%' AND (ph.frequency != 'sliding scale' OR ph.frequency IS NULL))) THEN 1 ELSE 0 END) = 0
        AND MAX(CASE WHEN pr.drug LIKE '%Regular%' AND ph.frequency = 'sliding scale' THEN 1 ELSE 0 END) = 0
        THEN 'Basal'
      WHEN MAX(CASE WHEN pr.drug LIKE '%Glargine%' OR pr.drug LIKE '%Detemir%' OR pr.drug LIKE '%NPH%' THEN 1 ELSE 0 END) = 0
        AND MAX(CASE WHEN (pr.drug LIKE '%Lispro%' OR pr.drug LIKE '%Aspart%' OR pr.drug LIKE '%Glulisine%' OR (pr.drug LIKE '%Regular%' AND (ph.frequency != 'sliding scale' OR ph.frequency IS NULL))) THEN 1 ELSE 0 END) = 1
        AND MAX(CASE WHEN pr.drug LIKE '%Regular%' AND ph.frequency = 'sliding scale' THEN 1 ELSE 0 END) = 0
        THEN 'Bolus'
      WHEN MAX(CASE WHEN pr.drug LIKE '%Glargine%' OR pr.drug LIKE '%Detemir%' OR pr.drug LIKE '%NPH%' THEN 1 ELSE 0 END) = 0
        AND MAX(CASE WHEN (pr.drug LIKE '%Lispro%' OR pr.drug LIKE '%Aspart%' OR pr.drug LIKE '%Glulisine%' OR (pr.drug LIKE '%Regular%' AND (ph.frequency != 'sliding scale' OR ph.frequency IS NULL))) THEN 1 ELSE 0 END) = 0
        AND MAX(CASE WHEN pr.drug LIKE '%Regular%' AND ph.frequency = 'sliding scale' THEN 1 ELSE 0 END) = 1
        THEN 'Sliding-Scale'
      ELSE 'Other'
    END AS regimen
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON ep.subject_id = pr.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph 
    ON pr.pharmacy_id = ph.pharmacy_id
  WHERE pr.starttime BETWEEN ep.admittime AND ep.admittime + INTERVAL '24 hours'
  GROUP BY 1
),

final_12h_regimen AS (
  SELECT 
    ep.subject_id,
    CASE
      WHEN MAX(CASE WHEN pr.drug LIKE '%Glargine%' OR pr.drug LIKE '%Detemir%' OR pr.drug LIKE '%NPH%' THEN 1 ELSE 0 END) = 1
        AND MAX(CASE WHEN (pr.drug LIKE '%Lispro%' OR pr.drug LIKE '%Aspart%' OR pr.drug LIKE '%Glulisine%' OR (pr.drug LIKE '%Regular%' AND (ph.frequency != 'sliding scale' OR ph.frequency IS NULL))) THEN 1 ELSE 0 END) = 1
        THEN 'Basal-Bolus'
      WHEN MAX(CASE WHEN pr.drug LIKE '%Glargine%' OR pr.drug LIKE '%Detemir%' OR pr.drug LIKE '%NPH%' THEN 1 ELSE 0 END) = 1
        AND MAX(CASE WHEN (pr.drug LIKE '%Lispro%' OR pr.drug LIKE '%Aspart%' OR pr.drug LIKE '%Glulisine%' OR (pr.drug LIKE '%Regular%' AND (ph.frequency != 'sliding scale' OR ph.frequency IS NULL))) THEN 1 ELSE 0 END) = 0
        AND MAX(CASE WHEN pr.drug LIKE '%Regular%' AND ph.frequency = 'sliding scale' THEN 1 ELSE 0 END) = 0
        THEN 'Basal'
      WHEN MAX(CASE WHEN pr.drug LIKE '%Glargine%' OR pr.drug LIKE '%Detemir%' OR pr.drug LIKE '%NPH%' THEN 1 ELSE 0 END) = 0
        AND MAX(CASE WHEN (pr.drug LIKE '%Lispro%' OR pr.drug LIKE '%Aspart%' OR pr.drug LIKE '%Glulisine%' OR (pr.drug LIKE '%Regular%' AND (ph.frequency != 'sliding scale' OR ph.frequency IS NULL))) THEN 1 ELSE 0 END) = 1
        AND MAX(CASE WHEN pr.drug LIKE '%Regular%' AND ph.frequency = 'sliding scale' THEN 1 ELSE 0 END) = 0
        THEN 'Bolus'
      WHEN MAX(CASE WHEN pr.drug LIKE '%Glargine%' OR pr.drug LIKE '%Detemir%' OR pr.drug LIKE '%NPH%' THEN 1 ELSE 0 END) = 0
        AND MAX(CASE WHEN (pr.drug LIKE '%Lispro%' OR pr.drug LIKE '%Aspart%' OR pr.drug LIKE '%Glulisine%' OR (pr.drug LIKE '%Regular%' AND (ph.frequency != 'sliding scale' OR ph.frequency IS NULL))) THEN 1 ELSE 0 END) = 0
        AND MAX(CASE WHEN pr.drug LIKE '%Regular%' AND ph.frequency = 'sliding scale' THEN 1 ELSE 0 END) = 1
        THEN 'Sliding-Scale'
      ELSE 'Other'
    END AS regimen
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON ep.subject_id = pr.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph 
    ON pr.pharmacy_id = ph.pharmacy_id
  WHERE pr.starttime BETWEEN ep.dischtime - INTERVAL '12 hours' AND ep.dischtime
  GROUP BY 1
),

total_patients AS (
  SELECT COUNT(*) AS total FROM eligible_patients
)

SELECT 
  regimen,
  ROUND((first_cnt * 100.0) / total, 2) AS first_24h_pct,
  ROUND((final_cnt * 100.0) / total, 2) AS final_12h_pct,
  ROUND(((final_cnt - first_cnt) * 100.0) / total, 2) AS change_pct
FROM (
  SELECT 
    'Basal-Bolus' AS regimen,
    (SELECT COUNT(*) FROM first_24h_regimen WHERE regimen = 'Basal-Bolus') AS first_cnt,
    (SELECT COUNT(*) FROM final_12h_regimen WHERE regimen = 'Basal-Bolus') AS final_cnt
  UNION ALL
  SELECT 
    'Basal',
    (SELECT COUNT(*) FROM first_24h_regimen WHERE regimen = 'Basal'),
    (SELECT COUNT(*) FROM final_12h_regimen WHERE regimen = 'Basal')
  UNION ALL
  SELECT 
    'Bolus',
    (SELECT COUNT(*) FROM first_24h_regimen WHERE regimen = 'Bolus'),
    (SELECT COUNT(*) FROM final_12h_regimen WHERE regimen = 'Bolus')
  UNION ALL
  SELECT 
    'Sliding-Scale',
    (SELECT COUNT(*) FROM first_24h_regimen WHERE regimen = 'Sliding-Scale'),
    (SELECT COUNT(*) FROM final_12h_regimen WHERE regimen = 'Sliding-Scale')
) AS regimen_counts
CROSS JOIN total_patients;