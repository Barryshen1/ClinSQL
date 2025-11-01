WITH ace_cohort AS (
  SELECT 
    p.subject_id,
    AVG(
      CASE 
        WHEN pr.stoptime > pr.starttime 
        THEN DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY)
        ELSE NULL 
      END
    ) AS avg_duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id 
    AND a.hadm_id = pr.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND (LOWER(pr.drug) LIKE '%lisinopril%'
      OR LOWER(pr.drug) LIKE '%enalapril%'
      OR LOWER(pr.drug) LIKE '%ramipril%'
      OR LOWER(pr.drug) LIKE '%captopril%'
      OR LOWER(pr.drug) LIKE '%benazepril%'
      OR LOWER(pr.drug) LIKE '%quinapril%'
      OR LOWER(pr.drug) LIKE '%perindopril%'
      OR LOWER(pr.drug) LIKE '%trandolapril%'
      OR LOWER(pr.drug) LIKE '%moexipril%'
      OR LOWER(pr.drug) LIKE '%fosinopril%')
  GROUP BY p.subject_id
  HAVING AVG(
    CASE 
      WHEN pr.stoptime > pr.starttime 
      THEN DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY)
      ELSE NULL 
    END
  ) > 0
)

SELECT 
  STDDEV(avg_duration_days) AS sd_inpatient_ace_duration_days
FROM ace_cohort;