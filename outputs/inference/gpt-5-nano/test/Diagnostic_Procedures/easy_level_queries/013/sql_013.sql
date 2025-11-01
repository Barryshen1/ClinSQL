WITH valve_procs AS (
  SELECT p.subject_id, p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%valve%'
    AND (
         LOWER(d.long_title) LIKE '%replacement%' 
      OR LOWER(d.long_title) LIKE '%repair%' 
      OR LOWER(d.long_title) LIKE '%valvuloplasty%' 
      OR LOWER(d.long_title) LIKE '%annuloplasty%'
    )
),
age_filt AS (
  SELECT a.hadm_id, a.subject_id,
         (pat.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pat.anchor_year)) AS age_at_admission,
         pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
)
SELECT MIN(cnt) AS min_distinct_valve_procedures_per_hosp_admission
FROM (
  SELECT af.hadm_id, COUNT(DISTINCT vp.icd_code) AS cnt
  FROM valve_procs vp
  JOIN age_filt af ON vp.hadm_id = af.hadm_id AND vp.subject_id = af.subject_id
  WHERE af.gender = 'F'
    AND af.age_at_admission BETWEEN 57 AND 67
  GROUP BY af.hadm_id
) t;