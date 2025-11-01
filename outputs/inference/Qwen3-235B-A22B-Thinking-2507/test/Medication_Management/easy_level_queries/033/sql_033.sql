SELECT
  AVG(
    TIMESTAMP_DIFF(
      COALESCE(pres.stoptime, adm.dischtime),
      pres.starttime,
      SECOND
    ) / (24 * 60 * 60.0)
  ) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON p.subject_id = adm.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
  ON adm.hadm_id = pres.hadm_id AND adm.subject_id = pres.subject_id
WHERE
  p.gender = 'F'
  AND (
    EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age)
  ) BETWEEN 77 AND 87
  AND pres.starttime >= adm.admittime  -- Ensures prescription started during admission
  AND pres.starttime <= adm.dischtime  -- Ensures valid in-hospital prescription
  AND REGEXP_CONTAINS(LOWER(pres.drug), r'losartan|valsartan|irbesartan|candesartan|telmisartan|olmesartan|eprosartan|azilsartan');