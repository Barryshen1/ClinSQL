SELECT MAX(proc_count) AS max_distinct_echocardiography_procedures
FROM (
  SELECT p.subject_id, COUNT(DISTINCT h.hcpcs_cd) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
    ON p.subject_id = h.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d
    ON h.hcpcs_cd = d.code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(d.short_description) LIKE '%echocardiography%'
  GROUP BY p.subject_id
) subquery;