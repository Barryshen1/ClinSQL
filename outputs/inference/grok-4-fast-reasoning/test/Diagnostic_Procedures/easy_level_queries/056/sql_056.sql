WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 43 AND 53
),
mcs_procedures AS (
  SELECT DISTINCT pi.subject_id, pi.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%assist%'
     OR LOWER(dip.long_title) LIKE '%balloon%'
     OR LOWER(dip.long_title) LIKE '%ecmo%'
)
SELECT APPROX_QUANTILES(num_procs, 3)[OFFSET(0)] AS p25th_percentile
FROM (
  SELECT ep.subject_id, COUNT(mcs.icd_code) AS num_procs
  FROM eligible_patients ep
  LEFT JOIN mcs_procedures mcs
    ON ep.subject_id = mcs.subject_id
  GROUP BY ep.subject_id
);