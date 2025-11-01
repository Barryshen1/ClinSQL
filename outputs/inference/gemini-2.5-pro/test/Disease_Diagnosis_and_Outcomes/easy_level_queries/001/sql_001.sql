WITH HadmWithBothDiagnoses AS (
  -- This CTE identifies hospital admissions (hadm_id) where a patient was diagnosed
  -- with both an Upper GI Bleed and a COPD Exacerbation.
  SELECT
    dia.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON dia.icd_code = d.icd_code AND dia.icd_version = d.icd_version
  WHERE
    -- Condition 1: Upper GI Bleed (UGIB)
    (
      LOWER(d.long_title) LIKE '%upper gastrointestinal bleed%'
      OR LOWER(d.long_title) LIKE '%upper gastrointestinal hemorrhage%'
    )
    OR
    -- Condition 2: COPD Exacerbation
    (
      LOWER(d.long_title) LIKE '%chronic obstructive pulmonary disease%'
      AND LOWER(d.long_title) LIKE '%exacerbation%'
    )
  GROUP BY
    dia.hadm_id
  HAVING
    -- This clause ensures that diagnoses for BOTH conditions were recorded for the hadm_id.
    COUNT(DISTINCT CASE
      WHEN (LOWER(d.long_title) LIKE '%upper gastrointestinal bleed%' OR LOWER(d.long_title) LIKE '%upper gastrointestinal hemorrhage%') THEN 'ugib'
      WHEN (LOWER(d.long_title) LIKE '%chronic obstructive pulmonary disease%' AND LOWER(d.long_title) LIKE '%exacerbation%') THEN 'copd_exac'
    END) = 2
)
SELECT
  AVG(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60)) AS average_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN
  HadmWithBothDiagnoses
  ON adm.hadm_id = HadmWithBothDiagnoses.hadm_id
WHERE
  -- Apply the demographic filters for the patient cohort
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 86 AND 96;