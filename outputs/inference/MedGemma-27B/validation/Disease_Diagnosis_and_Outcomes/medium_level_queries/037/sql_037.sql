WITH PatientInfo AS (
  -- Select subject_id and age for the target patient
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 57 -- Replace 57 with the actual subject_id of the patient
),
SepsisPatients AS (
  -- Identify patients with sepsis based on ICD-9/10 codes
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  ON
    a.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('99592', '4681', '4682', '4683', '4684', '4685', '4686', '4687', '4688', '4689', '4690', '4691', '4692', '4693', '4694', '4695', '4696', '4697', '4698', '4699', '4700', '4701', '4702', '4703', '4704', '4705', '4706', '4707', '4708', '4709', '4710', '4711', '4712', '4713', '4714', '4715', '4716', '4717', '4718', '4719', '4720', '4721', '4722', '4723', '4724', '4725', '4726', '4727', '4728', '4729', '4730', '4731', '4732', '4733', '4734', '4735', '4736', '4737', '4738', '4739', '4740', '4741', '4742', '4743', '4744', '4745', '4746', '4747', '4748', '4749', '4750', '4751', '4752', '4753', '4754', '4755', '4756', '4757', '4758', '4759', '4760', '4761', '4762', '4763', '4764', '4765', '4766', '4767', '4768', '4769', '4770', '4771', '4772', '477;