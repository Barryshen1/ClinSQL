WITH eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    -- Admit duration at least 72 hours
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    -- Diabetes mellitus type 2: existence of a diabetes II diagnosis for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (dd.long_title LIKE '%Type 2 diabetes%' OR dd.long_title LIKE '%diabetes mellitus type 2%')
    )
    -- Heart failure: existence of a HF diagnosis for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        ON di2.icd_code = dd2.icd_code AND di2.icd_version = dd2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND (dd2.long_title LIKE '%Heart failure%' OR dd2.long_title LIKE '%congestive heart failure%')
    )
)

-- Compute flags for GLP-1 initiation within 12h and within 72h, then summarize rates
SELECT
  COUNT(*) AS total_admissions,
  AVG(init12h) AS initiation12h_rate,
  AVG(by72h) AS by72h_rate,
  AVG(by72h) - AVG(init12h) AS net_percentage_point_change
FROM (
  SELECT
    e.hadm_id,
    -- 1 if a GLP-1 prescription started within 12h of admission, else 0
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = e.subject_id
        AND pr.hadm_id = e.hadm_id
        AND (
          LOWER(pr.drug) LIKE '%liraglutide%' OR
          LOWER(pr.drug) LIKE '%exenatide%' OR
          LOWER(pr.drug) LIKE '%dulaglutide%' OR
          LOWER(pr.drug) LIKE '%semaglutide%' OR
          LOWER(pr.drug) LIKE '%lixisenatide%'
        )
        AND pr.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 12 HOUR)
    ) THEN 1 ELSE 0 END AS init12h,
    -- 1 if a GLP-1 prescription started within 72h of admission, else 0
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = e.subject_id
        AND pr.hadm_id = e.hadm_id
        AND (
          LOWER(pr.drug) LIKE '%liraglutide%' OR
          LOWER(pr.drug) LIKE '%exenatide%' OR
          LOWER(pr.drug) LIKE '%dulaglutide%' OR
          LOWER(pr.drug) LIKE '%semaglutide%' OR
          LOWER(pr.drug) LIKE '%lixisenatide%'
        )
        AND pr.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 72 HOUR)
    ) THEN 1 ELSE 0 END AS by72h
  FROM eligible e
);