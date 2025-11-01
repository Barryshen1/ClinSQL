WITH first_hadm AS (
  -- find each subject's first hospital admission (index admission)
  SELECT
    subject_id,
    ARRAY_AGG(hadm_id ORDER BY admittime ASC LIMIT 1)[OFFSET(0)] AS first_hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY
    subject_id
),
index_admissions AS (
  -- restrict to those first (index) admissions
  SELECT a.*
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN first_hadm f
    ON a.subject_id = f.subject_id
   AND a.hadm_id = f.first_hadm_id
)
SELECT
  COUNT(DISTINCT a.hadm_id) AS num_index_admissions_meeting_criteria
FROM
  index_admissions a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
 AND d.seq_num = 1  -- principal diagnosis
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON d.icd_code = di.icd_code
 AND CAST(d.icd_version AS STRING) = CAST(di.icd_version AS STRING)
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND UPPER(a.insurance) LIKE '%MEDICARE%'
  AND UPPER(a.admission_location) LIKE '%EMERGENCY%'
  AND UPPER(di.long_title) LIKE '%DIABETIC KETOACIDOSIS%';