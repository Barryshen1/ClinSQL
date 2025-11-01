WITH cohort AS (
  -- Male inpatients age 49-59 with both T2DM and Heart Failure diagnoses on the same admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- require Type 2 Diabetes diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
        AND (LOWER(dd.long_title) LIKE '%type 2%' OR LOWER(dd.long_title) LIKE '%type ii%' OR LOWER(dd.long_title) LIKE '%type ii%')
    )
    -- require Heart Failure diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
        ON d2.icd_code = dd2.icd_code
        AND d2.icd_version = dd2.icd_version
      WHERE d2.hadm_id = a.hadm_id
        AND (
          LOWER(dd2.long_title) LIKE '%heart failure%'
          OR LOWER(dd2.long_title) LIKE '%congestive%'
          OR LOWER(dd2.long_title) LIKE '%cardiac failure%'
        )
    )
),

meds_union AS (
  -- union medication sources: prescriptions.drug and pharmacy.medication
  SELECT
    subject_id,
    hadm_id,
    starttime AS med_start,
    stoptime AS med_stop,
    LOWER(drug) AS med_text
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    hadm_id IS NOT NULL

  UNION ALL

  SELECT
    subject_id,
    hadm_id,
    starttime AS med_start,
    stoptime AS med_stop,
    LOWER(medication) AS med_text
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE
    hadm_id IS NOT NULL
),

meds_mapped AS (
  -- map medications to the four drug classes based on keywords
  SELECT
    m.subject_id,
    m.hadm_id,
    m.med_start,
    m.med_stop,
    CASE
      WHEN m.med_text LIKE '%insulin%' OR m.med_text LIKE '%metformin%' OR m.med_text LIKE '%glipizide%' OR m.med_text LIKE '%glyburide%' OR m.med_text LIKE '%glimepiride%' OR m.med_text LIKE '%sitagliptin%' OR m.med_text LIKE '%linagliptin%' OR m.med_text LIKE '%gliptin%' OR m.med_text LIKE '%gliflozin%' OR m.med_text LIKE '%dapagliflozin%' OR m.med_text LIKE '%empagliflozin%' OR m.med_text LIKE '%canagliflozin%' OR m.med_text LIKE '%glitazone%' OR m.med_text LIKE '%liraglutide%' OR m.med_text LIKE '%semaglutide%' OR m.med_text LIKE '%repaglinide%' OR m.med_text LIKE '%diabet%' THEN 'Antidiabetic'
      WHEN m.med_text LIKE '%metoprolol%' OR m.med_text LIKE '%atenolol%' OR m.med_text LIKE '%propranolol%' OR m.med_text LIKE '%carvedilol%' OR m.med_text LIKE '%bisoprolol%' OR m.med_text LIKE '%nadolol%' OR m.med_text LIKE '%timolol%' OR m.med_text LIKE '%nebivolol%' OR m.med_text LIKE '%labetalol%' OR m.med_text LIKE '%sotalol%' OR m.med_text LIKE '%acebutolol%' OR m.med_text LIKE '%olol%' THEN 'Beta-Blocker'
      WHEN m.med_text LIKE '%lisinopril%' OR m.med_text LIKE '%enalapril%' OR m.med_text LIKE '%ramipril%' OR m.med_text LIKE '%benazepril%' OR m.med_text LIKE '%perindopril%' OR m.med_text LIKE '%pril%' OR m.med_text LIKE '%losartan%' OR m.med_text LIKE '%valsartan%' OR m.med_text LIKE '%candesartan%' OR m.med_text LIKE '%irbesartan%' OR m.med_text LIKE '%sacubitril%' OR m.med_text LIKE '%sartan%' OR m.med_text LIKE '%angiotensin%' THEN 'ACEi/ARB/ARNI'
      WHEN m.med_text LIKE '%furosemide%' OR m.med_text LIKE '%lasix%' OR m.med_text LIKE '%bumetanide%' OR m.med_text LIKE '%torsemide%' OR m.med_text LIKE '%loop diuretic%' THEN 'Loop Diuretic'
      ELSE NULL
    END AS drug_class
  FROM
    meds_union m
  WHERE
    m.med_text IS NOT NULL
),

-- For each admission and drug class determine if any medication overlaps first24 and final48 windows
per_adm_class_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    mm.drug_class,
    -- define window boundaries
    TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) AS first24_end,
    TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AS final48_start
  FROM
    cohort c
  CROSS JOIN (
    SELECT DISTINCT drug_class FROM meds_mapped WHERE drug_class IS NOT NULL
  ) mm
),

exposure_flags AS (
  -- For each admission and drug class, check for any med exposure overlapping each window
  SELECT
    f.subject_id,
    f.hadm_id,
    f.drug_class,
    -- did any med of this class overlap first 24h?
    MAX(CASE
      WHEN m.med_start <= f.first24_end
           AND (m.med_stop IS NULL OR m.med_stop >= f.admittime)
      THEN 1 ELSE 0 END) AS on_first24_flag,
    -- did any med of this class overlap final 48h?
    MAX(CASE
      WHEN m.med_start <= f.dischtime
           AND (m.med_stop IS NULL OR m.med_stop >= f.final48_start)
      THEN 1 ELSE 0 END) AS on_final48_flag
  FROM
    per_adm_class_flags f
  LEFT JOIN
    meds_mapped m
  ON m.hadm_id = f.hadm_id
     AND m.drug_class = f.drug_class
  GROUP BY
    f.subject_id, f.hadm_id, f.drug_class
),

-- Summarize counts across cohort (distinct admissions)
summary AS (
  SELECT
    drug_class,
    COUNT(DISTINCT CASE WHEN 1=1 THEN hadm_id END) AS cohort_admissions_with_class_possible, -- number of admissions considered for this class
    SUM(on_first24_flag) AS on_first_count,
    SUM(on_final48_flag) AS on_final_count,
    SUM(CASE WHEN on_first24_flag = 1 AND on_final48_flag = 1 THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN on_first24_flag = 0 AND on_final48_flag = 1 THEN 1 ELSE 0 END) AS initiated_count,
    SUM(CASE WHEN on_first24_flag = 1 AND on_final48_flag = 0 THEN 1 ELSE 0 END) AS discontinued_count
  FROM
    exposure_flags
  GROUP BY
    drug_class
),

-- total cohort size (number of admissions meeting clinical inclusion independent of drug class)
cohort_size AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions
  FROM cohort
)

SELECT
  s.drug_class,
  cs.total_admissions AS cohort_size,
  s.cohort_admissions_with_class_possible,
  s.on_first_count,
  ROUND(100.0 * s.on_first_count / cs.total_admissions, 2) AS pct_on_first24,
  s.on_final_count,
  ROUND(100.0 * s.on_final_count / cs.total_admissions, 2) AS pct_on_final48,
  s.continued_count,
  s.initiated_count,
  s.discontinued_count
FROM
  summary s
CROSS JOIN
  cohort_size cs
ORDER BY
  s.drug_class;