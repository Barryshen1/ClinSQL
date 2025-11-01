SELECT
  AVG(DATETIME_DIFF(pr.stoptime, pr.starttime, DAY)) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` ad
  ON pr.hadm_id = ad.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON pr.subject_id = pt.subject_id
WHERE
  pt.gender = 'F'
  AND (DATETIME_DIFF(ad.admittime, DATETIME(pt.anchor_year, 1, 1, 0, 0, 0), YEAR) + pt.anchor_age) BETWEEN 77 AND 87
  AND pr.drug_type = 'MAIN'
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND REGEXP_CONTAINS(UPPER(pr.drug), r'LOSARTAN|VALSARTAN|TELMISARTAN|IRBESARTAN|CANDESARTAN|OLMESARTAN|EPROSARTAN');