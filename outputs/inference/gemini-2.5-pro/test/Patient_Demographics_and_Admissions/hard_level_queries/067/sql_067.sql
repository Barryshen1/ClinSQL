WITH QualifyingAdmissions AS (
  -- Step 1 & 2 & 3: Select all admissions that meet the patient, admission, and diagnosis criteria
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND dx.seq_num = 1
    AND LOWER(d_dx.long_title) LIKE '%bowel obstruction%'
),
RankedAdmissions AS (
  -- Step 4: Rank the qualifying admissions for each patient by time
  SELECT
    hadm_id,
    ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY admittime ASC) AS rn
  FROM
    QualifyingAdmissions
)
-- Step 5: Count the index admissions (the first one for each patient)
SELECT
  COUNT(hadm_id) AS number_of_index_admissions
FROM
  RankedAdmissions
WHERE
  rn = 1;